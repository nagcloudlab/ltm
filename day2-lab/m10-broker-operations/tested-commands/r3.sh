#!/bin/bash
cd /home/student/lab
Q(){ echo "\$ sudo rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers"; sudo rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers; }
echo "### 1 no consumers $(date +%T)"
./publish.py 200
Q
echo "### 2 noack"
nohup ./sms-noack.py > noack.out 2>&1 &
sleep 8; Q
sudo rabbitmqctl list_consumers queue_name channel_pid ack_required prefetch_count
sudo rabbitmqctl list_channels name messages_unacknowledged prefetch_count
head -2 noack.out
echo "### 3 kill noack"
pkill -f sms-noack.py; sleep 5; Q
echo "### 4 poison"
sudo rabbitmqctl purge_queue sms
rabbitmqadmin publish exchange=payments routing_key=payment.completed payload='{"event":"PaymentCompleted","id":"P900","amount":500}'
nohup ./sms-poison.py > poison.out 2>&1 &
sleep 10
head -4 poison.out; wc -l poison.out
Q
rabbitmqadmin list queues name messages messages_unacknowledged message_stats.redeliver_details.rate
pkill -f sms-poison.py; sleep 3
sudo rabbitmqctl purge_queue sms
echo "### 5 dlq flood"
nohup ./sms-rejectall.py > reject.out 2>&1 &
sleep 5
./publish.py 500
sleep 8; Q
echo "### dlq message"
curl -s -u guest:guest -H 'content-type: application/json' -X POST -d '{"count":1,"ackmode":"reject_requeue_true","encoding":"auto"}' http://localhost:15672/api/queues/%2F/sms.dlq/get | python3 -m json.tool
pkill -f sms-rejectall.py; sleep 3
echo "### 6 shovel"
sudo rabbitmq-plugins enable rabbitmq_shovel rabbitmq_shovel_management
nohup ./sms-consumer.py > good.out 2>&1 &
sleep 5
sudo rabbitmqctl set_parameter shovel dlq-replay '{"src-protocol":"amqp091","src-uri":"amqp://","src-queue":"sms.dlq","dest-protocol":"amqp091","dest-uri":"amqp://","dest-queue":"sms","src-delete-after":"queue-length"}'
sleep 3
sudo rabbitmqctl shovel_status
sleep 10
Q
sudo rabbitmqctl shovel_status
sudo rabbitmqctl list_parameters
head -2 good.out; wc -l good.out
pkill -f sms-consumer.py
echo "### 7 purge"
./publish.py 5
sudo rabbitmqctl purge_queue sms
echo "### 8 disk alarm $(date +%T)"
sudo rabbitmqctl set_disk_free_limit 5000GB
sleep 15
sudo rabbitmq-diagnostics alarms
sudo rabbitmq-diagnostics check_local_alarms; echo "exit=$?"
(timeout 30 ./publish.py 3; echo "publish exit=$?") &
sleep 10
sudo rabbitmqctl list_connections name state
wait
sudo rabbitmqctl set_disk_free_limit 50MB
sleep 15
sudo rabbitmq-diagnostics alarms
Q
sudo grep -i -E "alarm|blocked|disk" /var/log/rabbitmq/rabbit@*.log | tail -12
echo "### DONE"
