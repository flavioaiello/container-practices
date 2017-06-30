# Docker best practices

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
...

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


more to come ... stay tuned
