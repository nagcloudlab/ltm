#!/bin/bash
export PATH=$PATH:/opt/kafka/bin
B="--bootstrap-server localhost:9092"
cd /home/student/lab
pkill -f "group notification-service"; sleep 3
echo "### no such group"
kafka-consumer-groups.sh $B --describe --group notifcation-service
echo "### no topic scope"
kafka-consumer-groups.sh $B --group notification-service --reset-offsets --to-earliest --dry-run 2>&1 | head -3
echo "### awk"
kafka-consumer-groups.sh $B --describe --group notification-service 2>/dev/null | awk '{print $3, $6}'
echo "### datetime $(date +%T) TZ=$(cat /etc/timezone 2>/dev/null) $(date +%Z)"
T=$(date -d '-15 min' +%Y-%m-%dT%H:%M:%S.000)
echo "T=$T"
echo "\$ kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group notification-service --topic payments --reset-offsets --to-datetime $T --dry-run"
kafka-consumer-groups.sh $B --group notification-service --topic payments --reset-offsets --to-datetime $T --dry-run
kafka-consumer-groups.sh $B --group notification-service --topic payments --reset-offsets --to-datetime $T --execute
kafka-consumer-groups.sh $B --describe --group notification-service
echo "### DONE"
