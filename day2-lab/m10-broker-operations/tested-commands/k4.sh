#!/bin/bash
export PATH=$PATH:/opt/kafka/bin
B="--bootstrap-server localhost:9092"
cd /home/student/lab
P(){ kafka-console-producer.sh $B --topic payments --reader-property parse.key=true --reader-property key.separator=: ; }
D(){ echo "\$ kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group $1 $2"; kafka-consumer-groups.sh $B --describe --group $1 $2; }
echo "### configs $(date +%T)"
kafka-configs.sh $B --describe --all --topic payments | grep -E "retention.ms|retention.bytes|segment.bytes|cleanup.policy"
kafka-configs.sh $B --describe --all --broker 1 | grep -E "group.initial.rebalance.delay.ms|log.retention.hours|log.dirs|group.consumer.session.timeout.ms|group.consumer.heartbeat.interval.ms|group.classic.min.session|group.max.session|offsets.retention.minutes|log.retention.check"
echo "### data dir"
sudo ls -l /var/lib/kafka | head -20
sudo ls -l /var/lib/kafka/payments-1
sudo du -sh /var/lib/kafka; df -h /var/lib/kafka
echo "### under-replicated"
kafka-topics.sh $B --describe --under-replicated-partitions; echo "(exit $?)"
echo "### hot key $(date +%T)"
pkill -f "group notification-service"; sleep 5
D notification-service
for i in $(seq 1 2000); do echo "acc-1001:{\"event\":\"PaymentCompleted\",\"id\":\"H$i\",\"amount\":500}"; done > hot.txt
for i in $(seq 1 150); do echo "acc-$((RANDOM%50+1000)):{\"event\":\"PaymentCompleted\",\"id\":\"R$i\",\"amount\":500}"; done >> hot.txt
P < hot.txt
D notification-service
echo "### four consumers $(date +%T)"
L0=$(wc -l < /opt/kafka/logs/server.log)
for n in 1 2 3 4; do nohup kafka-console-consumer.sh $B --topic payments --group notification-service --command-property client.id=sms-$n > c$n.out 2> c$n.err & sleep 8; done
sleep 30
D notification-service
D notification-service "--members"
D notification-service "--members --verbose"
D notification-service "--state"
echo "### reset while active"
kafka-consumer-groups.sh $B --group notification-service --topic payments --reset-offsets --to-earliest --execute
echo "### server.log rebalance lines"
tail -n +$L0 /opt/kafka/logs/server.log | grep -i -E "notification-service" | head -40
echo "### stop all $(date +%T)"
pkill -f "group notification-service"; sleep 60
tail -n +$L0 /opt/kafka/logs/server.log | grep -i -E "notification-service" | tail -15
D notification-service "--state"
echo "### DONE $(date +%T)"
