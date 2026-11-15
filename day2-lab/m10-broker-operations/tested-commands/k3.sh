#!/bin/bash
export PATH=$PATH:/opt/kafka/bin
B="--bootstrap-server localhost:9092"
cd /home/student/lab
gen(){ for i in $(seq $1 $2); do echo "acc-$((RANDOM%50+1000)):{\"event\":\"PaymentCompleted\",\"id\":\"P$i\",\"amount\":500}"; done; }
echo "### start consumer $(date +%T)"
nohup kafka-console-consumer.sh $B --topic payments --group notification-service > notif.out 2> notif.err &
sleep 40
gen 7 306 | kafka-console-producer.sh $B --topic payments --reader-property parse.key=true --reader-property key.separator=:
sleep 15
echo "### describe running $(date +%T)"
kafka-consumer-groups.sh $B --describe --group notification-service
echo "### describe state"
kafka-consumer-groups.sh $B --describe --group notification-service --state
echo "### describe members"
kafka-consumer-groups.sh $B --describe --group notification-service --members --verbose
echo "### list"
kafka-consumer-groups.sh $B --list
echo "### stop consumer $(date +%T)"
pkill -f "group notification-service"; sleep 10
gen 307 3306 | kafka-console-producer.sh $B --topic payments --reader-property parse.key=true --reader-property key.separator=:
echo "### describe stopped $(date +%T)"
kafka-consumer-groups.sh $B --describe --group notification-service
echo "### describe state stopped"
kafka-consumer-groups.sh $B --describe --group notification-service --state
echo "### reset dry-run $(date +%T)"
kafka-consumer-groups.sh $B --group notification-service --topic payments --reset-offsets --to-earliest --dry-run
echo "### reset shift-by dry-run"
kafka-consumer-groups.sh $B --group notification-service --topic payments --reset-offsets --shift-by -100 --dry-run
echo "### reset no mode"
kafka-consumer-groups.sh $B --group notification-service --topic payments --reset-offsets --to-earliest
echo "### DONE $(date +%T)"
