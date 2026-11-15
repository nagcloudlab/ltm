#!/bin/bash
r(){ echo; echo "\$ $*"; eval "$@" 2>&1; }
cd ~
r java -version
r sudo tar -xzf kafka_2.13-4.4.0.tgz -C /opt
r sudo mv /opt/kafka_2.13-4.4.0 /opt/kafka
r ls /opt/kafka
r ls /opt/kafka/bin \| head -30
r sudo useradd -r -s /usr/sbin/nologin kafka
r sudo mkdir -p /var/lib/kafka
r sudo chown -R kafka:kafka /opt/kafka /var/lib/kafka
r "grep -vE '^#|^\$' /opt/kafka/config/server.properties"
r sudo sed -i 's#^log.dirs=.*#log.dirs=/var/lib/kafka#' /opt/kafka/config/server.properties
r grep -E "'^(process.roles|node.id|listeners|controller|log.dirs|num.partitions|log.retention.hours)'" /opt/kafka/config/server.properties
r 'ID=$(/opt/kafka/bin/kafka-storage.sh random-uuid); echo $ID'
r sudo -u kafka /opt/kafka/bin/kafka-storage.sh format --standalone -t \$ID -c /opt/kafka/config/server.properties
r sudo ls /var/lib/kafka
sudo tee /etc/systemd/system/kafka.service >/dev/null <<'UNIT'
[Unit]
Description=Apache Kafka (KRaft)
After=network.target

[Service]
User=kafka
Environment=JAVA_HOME=/usr/lib/jvm/java-21-openjdk-arm64
Environment="KAFKA_HEAP_OPTS=-Xmx512m -Xms512m"
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
r cat /etc/systemd/system/kafka.service
r sudo systemctl daemon-reload
r sudo systemctl enable --now kafka
for i in $(seq 1 60); do grep -q "Kafka Server started" /opt/kafka/logs/server.log 2>/dev/null && break; sleep 2; done
r systemctl status kafka --no-pager \| head -8
r ps -o user,pid,comm -u kafka
r "sudo ss -lntp | grep -E ':909[23]'"
r grep -E "'started|Recorded new KRaft controller'" /opt/kafka/logs/server.log \| tail -4
r ls /opt/kafka/logs
B=/opt/kafka/bin
r $B/kafka-topics.sh --bootstrap-server localhost:9092 --create --topic payments --partitions 3 --replication-factor 1
r $B/kafka-topics.sh --bootstrap-server localhost:9092 --list
r $B/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic payments
r sudo ls /var/lib/kafka
r "printf 'PaymentCompleted PAY-1001\nPaymentCompleted PAY-1002\nPaymentCompleted PAY-1003\n' | $B/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic payments"
r $B/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --from-beginning --max-messages 3
r $B/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --from-beginning --max-messages 3
# groups: two consumers in notification-service
$B/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group notification-service --property print.partition=true > c1.out 2>&1 &
P1=$!
sleep 8
$B/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group notification-service --property print.partition=true > c2.out 2>&1 &
P2=$!
sleep 15
r $B/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list
r $B/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service --members --verbose
r "printf 'k1:PaymentCompleted PAY-2001\nk2:PaymentCompleted PAY-2002\nk3:PaymentCompleted PAY-2003\nk4:PaymentCompleted PAY-2004\nk5:PaymentCompleted PAY-2005\nk6:PaymentCompleted PAY-2006\n' | $B/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic payments --property parse.key=true --property key.separator=:"
sleep 5
r cat c1.out; r cat c2.out
r $B/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group fraud-check --from-beginning --max-messages 9 --property print.partition=true
r $B/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list
kill $P1 $P2; sleep 3
# keys
r "printf 'ACC-1001:PaymentCreated PAY-5001\nACC-2002:PaymentCreated PAY-5002\nACC-1001:PaymentCompleted PAY-5001\nACC-2002:PaymentCompleted PAY-5002\nACC-1001:RefundIssued PAY-5001\n' | $B/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic payments --property parse.key=true --property key.separator=:"
r $B/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group key-demo --from-beginning --max-messages 14 --property print.partition=true --property print.key=true
r "grep -E 'ERROR|WARN' /opt/kafka/logs/server.log | tail -3"
echo; echo ===DONE
