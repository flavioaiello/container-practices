#!/bin/sh

echo "*** Loop all env variables matching the substitution pattern for stage specific configuration ***"
env | grep -o '^.*=.*;.*' | while read VARIABLE; do
    PROPERTY=${VARIABLE#*=}
    echo "*** Set key ${PROPERTY%;*} to value ${PROPERTY#*;} ***"
    find /home/mytechuser -type f -exec sed -i "s|\${${PROPERTY%;*}}|${PROPERTY#*;}|g" {} +
done

for SERVICE in ${SERVICES}; do
    echo "*** Waiting for service ${SERVICE%:*} port ${SERVICE#*:} with timeout ${TIMEOUT:-60} ***"
    for i in $(seq ${TIMEOUT:-60}); do nc -z -w 7 ${SERVICE%:*} ${SERVICE#*:}; sleep 1; done || exit "$?"
done

echo "*** Fix permissions when mounting external volumes running on technical user ***"
chown -R mytechuser:mytechuser /data/database/

echo "*** Startup $0 suceeded now starting service using eval to expand CMD variables ***"
exec su-exec mytechuser $(eval echo "$@")
