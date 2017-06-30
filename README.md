# Docker best practices

## Produce generic images
Docker images should be as general as possible, at least they must be environment agnostic. For this purpose the concrete values must be provided by environment variables during startup. Environment variables keys must follow `IEEE Std 1003.1-2001`, restricting the direct usage. The value of environment variables is not restricted and can take any character. This constraint leads to the pattern `MY_KEY=my.complex.key;my.complex.value` as shown below:

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
for VARIABLE in $(env |grep -o '^.*=.*;.*'); do
    PROPERTY=${VARIABLE#*=}
    echo "*** Set key ${PROPERTY%;*} to value ${PROPERTY#*;} ***"
    find /home/myone -type f -exec sed -i "s|\${${PROPERTY%;*}}|${PROPERTY#*;}|g" {} +
done
```

## Run not as root
Running a process in a container as root is really bad practice. The switch user `su` command brings some TTY hassle and `gosu` is deprecated in the meantime. For this purpose now you can use `su-exec`, a really lean alternative included in alpine linux.

### Example `Dockerfile` excerpt
```
FROM alpine:3.6

RUN set -ex;\
    apk update;\
    apk upgrade;\
    apk add --no-cache su-exec;\
    rm -rf /var/cache/apk/*;\
    echo "*** Add myone system account ***";\
    addgroup -S myone;\
    adduser -S -D -h /home/myone -s /bin/false -G myone -g "myone system account" myone;\
    chown -R myone /home/myone

CMD ["su-exec", "myone", "myprocess"]
```

## Use a zombie reaper
This one is deprecated as soon the `init: true` property is available on docker compose v3.x recipes. For now, `tini` is recommended for single process containers and must be included as shown below:

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
exec su-exec myone "$@"
```
## Copy multiple directory structures at once
Create beside of the `Dockefile` a `files` folder taking all directory structures and according files that need to be copied to the docker image during the build:

### Example `Dockerfile` excerpt
```
# Add local files to image
COPY files /
```
The overlay action above copies the files as root due to `COPY` not following the `USER` directive. The most effective way to fix permissions in terms of space consumption is, to shift the directory switching the user as shown below:

### Example `Dockerfile` excerpt
```
# Add local files to image
COPY files /files

# Copy with fixed ownership for myone user
RUN set -ex;\
    su-exec myone cp -rf /files/. /
```

## Installing software as one-liner
This is a very simple operation a can be performed in a simple manner, in just one piped statement:

### Example `Dockerfile` excerpt
```
RUN set -ex;\
    curl -sSL https://mydomain.com/mysoftware.tar.gz | tar -C /usr/local/bin -xvz;\
    ...
```

## wait-for-it / wait-for
A pure shell section that will to be included in the `entrypoint.sh`. Waiting a predefined timespan for a service to be responsive. This is useful on the startup of your containers. The predicatable exit during the startup makes the container restart depending on the policy on your deploy section of the recipe.

### Example `entrypoint.sh` excerpt
```
#!/bin/sh

for SERVICE in ${SERVICES}; do
    echo "*** Waiting for service ${SERVICE%:*} port ${SERVICE#*:} with timeout ${TIMEOUT:-60} ***"
    timeout -t ${TIMEOUT:-60} sh -c -- "while ! nc -z ${SERVICE%:*} ${SERVICE#*:}; do sleep 1; done" || exit "$?"
done
```
Since it is a pure sh script snippet, it does not have any external dependencies.


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
Usually the source build takes place in advance natively or in a build container on the local or build system producing build artifacts. The runtime build eg. `docker build` afterwards sources those artifacts in to the docker image. This step ommits the version and the docker image must be versioned separately. It is recommended to provide this portion of information using the `--build-args` argument during the build. For this purpose use the `ARG` AND `LABEL` directive in the `Dockerfile`. This  enables you to report also the specific release of containers deployed using the `latest` tag.

### Example `Dockerfile` excerpt
```
ARG TAG
LABEL TAG=${TAG}
```

## Bill of Materials - BOM
tbd
```
apk info -vv
```

more to come ... stay tuned
