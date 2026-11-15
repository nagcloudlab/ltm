#!/bin/bash
export PATH=$PATH:/opt/kafka/bin
B="--bootstrap-server localhost:9092"
cd /home/student/lab
echo "### configs $(date +%T)"
kafka-configs.sh $B --describe --all --topic payments 2>&1 | grep -E "retention.ms|retention.bytes|segment.bytes|cleanup.policy|Dynamic configs|All configs"
kafka-configs.sh $B --describe --all --broker 1 2>&1 | grep -E "group.initial.rebalance.delay.ms|log.retention.hours|log.retention.ms|log.dirs=|group.consumer.session.timeout.ms|group.consumer.heartbeat.interval.ms|offsets.retention.minutes|log.retention.check|group.classic"
echo "### consumerconfig"
sed 's/level: WARN/level: INFO/I' /opt/kafka/config/tools-log4j2.yaml > /tmp/info-log4j2.yaml
KAFKA_LOG4J_OPTS="-Dlog4j2.configurationFile=/tmp/info-log4j2.yaml" kafka-console-consumer.sh $B --topic payments --group cfg-probe --max-messages 1 2>&1 | grep -E "^\s*(session.timeout.ms|heartbeat.interval.ms|max.poll.interval.ms|max.poll.records|auto.offset.reset|group.protocol|partition.assignment.strategy|enable.auto.commit|auto.commit.interval.ms) ="
kafka-consumer-groups.sh $B --delete --group cfg-probe
echo "### retention files"
sudo ls -l /var/lib/kafka/payments-1
sudo du -sh /var/lib/kafka/payments-*; df -h /var/lib/kafka | tail -1
grep -n "log.retention.hours\|log.segment.bytes\|log.dirs" /opt/kafka/config/server.properties
echo "### DONE"
