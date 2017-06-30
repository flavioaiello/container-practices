FROM alpine:3.6

ARG TAG
LABEL TAG=${TAG}

# Add local files to image
COPY files /files
    
RUN set -ex;\
    apk update;\
    apk upgrade;\
    apk add --no-cache su-exec tini;\
    rm -rf /var/cache/apk/*;\
    echo "*** Add myone system account ***";\
    addgroup -S myone;\
    adduser -S -D -h /home/myone -s /bin/false -G myone -g "myone system account" myone;\
    chown -R myone /home/myone

# Copy with fixed ownership for myone user
RUN set -ex;\
    su-exec myone cp -rf /files/. /
    
WORKDIR /home/myone

RUN set -ex;\
    curl -sSL https://mydomain.com/mysoftware.tar.gz | tar -C /usr/local/bin -xvz

ENTRYPOINT ["/sbin/tini", "--", "entrypoint.sh"]
CMD ["myprocess", "-myargument=true"]
