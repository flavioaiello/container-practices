# Docker best practices

## Switch user


## Exec


## wait-for-it / wait-for
A pure sh script that will wait a predefined timespan for a host and according port to be responsive. This is useful for containers on the startup phase on the `entrypoint.sh` script.

### Usage in `entrypoint.sh`
```
#!/bin/sh

for SERVICE in ${SERVICES}; do
    echo "*** Waiting for service ${SERVICE%:*} port ${SERVICE#*:} with timeout ${TIMEOUT:-60} ***"
    timeout -t ${TIMEOUT:-60} sh -c -- "while ! nc -z ${SERVICE%:*} ${SERVICE#*:}; do sleep 1; done" || exit "$?"
done
```
Since it is a pure sh script snippet, it does not have any external dependencies.

### Example on docker-compose.sh
```
version: '3.2'

services:

  myservice:
    image: myimage
    environment:
      - SERVICES=database:9000 observer:5001
      - TIMEOUT=120
```


more to come ... stay tuned
