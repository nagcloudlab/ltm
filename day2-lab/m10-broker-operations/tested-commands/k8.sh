#!/bin/bash
export PATH=$PATH:/opt/kafka/bin
B="--bootstrap-server localhost:9092"
echo "### TZ=Asia/Kolkata 11:44:12"
TZ=Asia/Kolkata kafka-consumer-groups.sh $B --group notification-service --topic payments --reset-offsets --to-datetime 2026-11-15T11:44:12.000 --dry-run
echo "### UTC 11:44:12 (should be later => latest offsets)"
kafka-consumer-groups.sh $B --group notification-service --topic payments --reset-offsets --to-datetime 2026-11-15T11:44:12.000 --dry-run
echo "### DONE"
