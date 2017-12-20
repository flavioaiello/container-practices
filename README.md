# The docker best practices blueprint

## Produce generic images
Docker images should be as general as possible, at least they must be environment agnostic. For this purpose the concrete values must be provided by environment variables during startup. Environment variables key names must follow `IEEE Std 1003.1-2001`, restricting the direct usage. The value of environment variables is not restricted and can take any character. This constraint leads to the pattern `MY_KEY=my.complex.key;my.complex.value` as shown below:

### Example `docker-compose.yml` excerpt
```
version: '3.2'

services:

  myservice:
    image: myimage
    environment:
      - DB_CONNECTION=my.complex.key;jdbc://foo.bar:1234/foodb
  ...
```

### Example `entrypoint.sh` excerpt
```
#!/bin/sh

echo "*** Loop all env variables matching the substitution pattern for stage specific configuration ***"
env | grep -o '^.*=.*;.*' | while read VARIABLE; do
    PROPERTY=${VARIABLE#*=}
    echo "*** Set key ${PROPERTY%;*} to value ${PROPERTY#*;} ***"
    find /home/mytechuser -type f -exec sed -i "s|\${${PROPERTY%;*}}|${PROPERTY#*;}|g" {} +
done
```

## Run as technical user
Running a process in a container as root is bad practice. The switch user `su` command brings TTY hassle and `gosu` is deprecated due to `su-exec` offering the same with less effort.

### Example `Dockerfile` excerpt
```
...
RUN set -ex;\
    ...
    apk add --no-cache su-exec;\
    ...
    echo "*** Add mytechuser system account ***";\
    addgroup -S mytechuser;\
    adduser -S -D -h /home/mytechuser -s /bin/false -G mytechuser -g "mytechuser system account" mytechuser;\
    chown -R mytechuser /home/mytechuser
...
ENTRYPOINT ["entrypoint.sh"]
CMD ["myprocess", "-myargument=true"]
```
### Example `entrypoint.sh` excerpt
```
#!/bin/sh
...
echo "*** Startup suceeded now starting service as PID 1 owned by technical user ***"
exec su-exec mytechuser "$@"
```

## Mount volumes as technical user
When mounting external volumes and having the process owned by a technical user, permission errors arise. This can be resolved by resetting the permissions during the container startup:

### Example `entrypoint.sh` excerpt
```
echo "*** Fix permissions when mounting external volumes running on technical user ***"
chown -R mytechuser:mytechuser /data/database/
```

## Cleanup zombie processes
Using Docker 1.13 or greater, tini is included in Docker itself. This includes all versions of Docker CE. To enable Tini, just pass the `--init` flag to `docker run`. When deploying using `docker stack deploy` or `docker-compose` this property is missing. As soon the `init: true` property is available on docker compose v3.x recipes, the explicit setup on `Dockerfile` and `entrypoint.sh` as shown below is deprecated.

### Example `Dockerfile` excerpt
```
RUN set -ex;\
    apk add --no-cache tini;\
    ...

ENTRYPOINT ["/sbin/tini", "--", "entrypoint.sh"]
CMD ["myprocess", "-myargument=true"]
```

### Example `entrypoint.sh` excerpt
```
#!/bin/sh

...

echo "*** Startup $0 suceeded now starting service ***"
exec su-exec mytechuser "$@"
```

## Expand environment variables in CMD
Lets say you want to start a java process inside a container. In this case you need further options and you want to start the process directly (eg. without the catalina.sh wrapper in case of tomcat). First of all start the process using the catalina.sh wrapper. Then inside the container grab the execution statement of your process using `ps ef|less`. Subdivide now to options and command section and this will be your new CMD.

### Example `Dockerfile` excerpt
```
...
ENV JAVA_OPTS -XX:+UnlockExperimentalVMOptions -XX:+UseCGroupMemoryLimitForHeap -XX:MaxRAMFraction=1 -XshowSettings:vm
...
ENTRYPOINT ["/sbin/tini", "--", "entrypoint.sh"]
CMD ["myprocess", "${JAVA_OPTS}", "-myargument=true"]
```

### Example `entrypoint.sh` excerpt
```
#!/bin/sh
...
echo "*** Startup $0 suceeded now starting service using eval to expand CMD variables ***"
exec su-exec mytechuser $(eval echo "$@")
```

## Copy directory structure at once
Create beside of the `Dockefile` a separated `files` directory taking the full structure and the according files that need to be copied to the docker image during the build:

### Example `Dockerfile` excerpt
```
# Add local files to image
COPY files /
```

`COPY` or `ADD` are not following the `USER` directive available on the `Dockerile` reference. The most effective way to fix permissions in terms of space consumption is, to shift the overlay directory structure impersonating the user as shown below:

### Example `Dockerfile` excerpt
```
# Add local files to image
COPY files /files

# Copy with fixed ownership for mytechuser user
RUN set -ex;\
    su-exec mytechuser cp -rf /files/. /
```

## Installing software as one-liner
This is a very simple operation and can be performed in just one piped statement:

### Example `Dockerfile` excerpt
```
RUN set -ex;\
    curl -sSL https://mydomain.com/mysoftware.tar.gz | tar -C /usr/local/bin -xvz;\
    ...
```
In case only the subdirectories are required:
```
RUN set -ex;\
    curl -sSL https://mydomain.com/mysoftware.tar.gz | tar -C /usr/local/bin -xvz --strip-components=1 mysoftware-${MYSOFTWARE_VERSION};\
    ...
```

## Service dependencies (wait-for-it / wait-for)
A pure shell excerpt that needs to be included in the `entrypoint.sh`. Waiting a predefined timespan for a service to be responsive. Exiting during the startup if the service is not reachable. This makes the container restart depending on the policy on your deploy section of the recipe. Since it is a pure sh script snippet, it does not have any external dependencies.

### Example `entrypoint.sh` excerpt - Waiting for tcp deamon
```
#!/bin/sh

for SERVICE in ${SERVICES}; do
    echo "*** Waiting for service ${SERVICE%:*} port ${SERVICE#*:} with timeout ${TIMEOUT:-60} ***"
    for (( i=1; i<=${TIMEOUT:-60}; i++ )); do nc -z -w 7 ${SERVICE%:*} ${SERVICE#*:}; sleep 1; done || exit "$?"
done

```
### Example `entrypoint.sh` excerpt - Waiting for http status 200
```
#!/bin/sh

for SERVICE in ${SERVICES}; do
    echo "*** Waiting for service ${SERVICE%:*} port ${SERVICE#*:} with timeout ${TIMEOUT:-60} ***"
    for (( i=1; i<=${TIMEOUT:-60}; i++ )); do while [ $(curl -sf -o /dev/null -w "%{http_code}" "http://${SERVICE%:*}:${SERVICE#*:}/") -ne "200" ]; do sleep 1; done; done" || exit "$?"
done
```

### Example `docker-compose.yml` excerpt
```
version: '3.2'

services:

  myservice:
    image: myimage
    environment:
      - SERVICES=database:9000 observer:5001
      - TIMEOUT=120
    deploy:
      restart_policy:
        condition: on-failure
        max_attempts: 3
```

## Release Tags
Usually the build of the software sources takes place natively or in a build container in advance on the local workstation or build system producing build artifacts like war-, jar- , etc. files. The runtime build eg. `docker build` afterwards sources those artifacts in to the docker image. This step ommits the version and the docker image must be versioned separately. It is recommended to provide this portion of information using the `--build-args` argument during the build. For this purpose use the `ARG` AND `LABEL` directive in the `Dockerfile`. This  enables deployment reporting, allowing also the `latest` tag to be reported with a specific release tag.

### Example `Dockerfile` excerpt
```
ARG TAG
LABEL TAG=${TAG}
```

## Bill of Materials (BOM)
The attack surface of a container is determined by the amount of additional packages provided with the software artifacts. Having a bill of materials available enables reporting to be processed for vulnerability checking. At the moment there is no way to have a `LABEL` filled with the content of `apk info -vv` during the `docker build`.

More to come ... stay tuned
