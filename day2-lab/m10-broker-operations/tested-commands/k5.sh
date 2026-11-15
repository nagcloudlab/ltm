#!/bin/bash
export PATH=$PATH:/opt/kafka/bin
B="--bootstrap-server localhost:9092"
cd /home/student/lab
D(){ echo "\$ kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group $1 $2"; kafka-consumer-groups.sh $B --describe --group $1 $2; }
L0=$(wc -l < /opt/kafka/logs/server.log)
echo "### storm start $(date +%T)"
nohup kafka-console-consumer.sh $B --topic payments --group notification-service --command-property client.id=sms-fast > fast.out 2> fast.err &
sleep 10
(kafka-console-consumer.sh $B --topic payments --group notification-service --command-property client.id=sms-slow --command-property max.poll.interval.ms=15000 2> slow.err | while read l; do sleep 0.05; done) &
sleep 25
PAD=$(head -c 200 /dev/zero | tr '\0' 'x')
for i in $(seq 1 8000); do echo "acc-$((RANDOM%50+1000)):{\"event\":\"PaymentCompleted\",\"id\":\"S$i\",\"amount\":500,\"note\":\"$PAD\"}"; done | kafka-console-producer.sh $B --topic payments --reader-property parse.key=true --reader-property key.separator=:
sleep 120
D notification-service "--state"
D notification-service
echo "### slow.err"
cat slow.err | cut -c1-600
echo "### fast.err"
cat fast.err | cut -c1-400
echo "### server.log"
tail -n +$L0 /opt/kafka/logs/server.log | grep -i "notification-service" | cut -c1-500 | head -60
pkill -f "group notification-service"; sleep 5
echo "### kip848 $(date +%T)"
L1=$(wc -l < /opt/kafka/logs/server.log)
for n in 1 2; do nohup kafka-console-consumer.sh $B --topic payments --group fraud-check --command-property group.protocol=consumer --command-property client.id=fraud-$n > f$n.out 2> f$n.err & sleep 15; done
sleep 20
D fraud-check "--state"
D fraud-check "--members"
D fraud-check
tail -n +$L1 /opt/kafka/logs/server.log | grep -i "fraud-check" | cut -c1-500 | head -30
head -5 f1.err
pkill -f "group fraud-check"
echo "### DONE $(date +%T)"
