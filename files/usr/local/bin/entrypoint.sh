#!/bin/sh

echo "*** Loop all env variables matching the substitution pattern for stage specific configuration ***"
for VARIABLE in $(env |grep -o '^.*=.*;.*'); do
    PROPERTY=${VARIABLE#*=}
    echo "*** Set key ${PROPERTY%;*} to value ${PROPERTY#*;} ***"
    find /home/mytmytechuser -type f -exec sed -i "s|\${${PROPERTY%;*}}|${PROPERTY#*;}|g" {} +
done

for SERVICE in ${SERVICES}; do
    echo "*** Waiting for service ${SERVICE%:*} port ${SERVICE#*:} with timeout ${TIMEOUT:-60} ***"
    timeout -t ${TIMEOUT:-60} sh -c -- "while ! nc -z ${SERVICE%:*} ${SERVICE#*:}; do sleep 1; done" || exit "$?"
done

echo "*** Fix permissions when mounting external volumes running on technical user ***"
chown -R mytechuser:mytechuser /data/database/

echo "*** Startup $0 suceeded now starting service owned by technical user ***"
exec su-exec myone "$@"
