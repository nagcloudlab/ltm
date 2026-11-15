#!/bin/bash
export PATH=$PATH:/opt/kafka/bin
B="--bootstrap-server localhost:9092"
cd /home/student/lab
L0=$(wc -l < /opt/kafka/logs/server.log)
echo "### storm2 start $(date +%T)"
nohup kafka-console-consumer.sh $B --topic payments --group notification-service --command-property client.id=sms-fast > /dev/null 2> fast2.err &
sleep 8
(kafka-console-consumer.sh $B --topic payments --group notification-service --command-property client.id=sms-slow --command-property max.poll.interval.ms=10000 2> slow2.err | while read l; do sleep 0.1; done) &
sleep 8
PAD=$(head -c 300 /dev/zero | tr '\0' 'x')
( for r in $(seq 1 12); do for i in $(seq 1 1500); do echo "acc-$((RANDOM%50+1000)):{\"event\":\"PaymentCompleted\",\"id\":\"T$r-$i\",\"note\":\"$PAD\"}"; done; sleep 10; done ) | kafka-console-producer.sh $B --topic payments --reader-property parse.key=true --reader-property key.separator=:
sleep 20
echo "### slow2.err poll timeouts: $(grep -c 'poll timeout has expired' slow2.err)"
tail -n +$L0 /opt/kafka/logs/server.log | grep -E "Stabilized group notification-service|left group" | cut -c1-260
kafka-consumer-groups.sh $B --describe --group notification-service --state
pkill -f "group notification-service"; sleep 5
echo "### DONE $(date +%T)"
