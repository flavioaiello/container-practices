## Docker best practices

### wait-for-it / wait-for
A pure sh script that will wait a predefined timespan for a host and according port to be responsive. This is useful for containers on the startup phase on the `entrypoint.sh` script. 

Since it is a pure sh script snippet, it does not have any external dependencies.

#### Usage with docker-compose.sh
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
