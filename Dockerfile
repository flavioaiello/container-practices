FROM alpine:3.7

ARG TAG
LABEL TAG=${TAG}

# Add local files to image
COPY files /files
    
RUN set -ex;\
    apk update;\
    apk upgrade;\
    apk add --no-cache su-exec tini;\
    rm -rf /var/cache/apk/*;\
    echo "*** Add mytechuser system account ***";\
    addgroup -S mytechuser;\
    adduser -S -D -h /home/mytechuser -s /bin/false -G mytechuser -g "mytechuser system account" mytechuser;\
    chown -R mytechuser /home/mytechuser

# Copy with fixed ownership for mytechuser user
RUN set -ex;\
    su-exec mytechuser cp -rf /files/. /
    
WORKDIR /home/mytechuser

VOLUME ["/data/database/"]

RUN set -ex;\
    curl -sSL https://mydomain.com/mysoftware.tar.gz | tar -C /usr/local/bin -xvz

ENTRYPOINT ["/sbin/tini", "--", "entrypoint.sh"]
CMD ["myprocess", "${JAVA_OPTS}", "-myargument=true"]
