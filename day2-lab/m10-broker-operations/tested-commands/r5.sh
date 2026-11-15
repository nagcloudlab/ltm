#!/bin/bash
cd /home/student/lab
echo "### quiz line"
rabbitmqadmin declare exchange name=quiz type=topic
rabbitmqadmin declare queue name=alerts
rabbitmqadmin declare binding source=quiz destination=alerts routing_key="*.failed"
rabbitmqadmin publish exchange=quiz routing_key=payment.failed payload=x
rabbitmqadmin publish exchange=quiz routing_key=payment.card.failed payload=x
rabbitmqadmin delete queue name=alerts; rabbitmqadmin delete exchange name=quiz
echo "### consumer timeout $(date +%T)"
sudo rabbitmqctl eval 'application:set_env(rabbit, consumer_timeout, 15000).'
sudo rabbitmqctl purge_queue sms
./publish.py 20
L0=$(sudo wc -l < /var/log/rabbitmq/rabbit@$(hostname).log)
nohup ./sms-noack.py > noack2.out 2>&1 &
sleep 100
tail -15 noack2.out | cut -c1-400
sudo tail -n +$L0 /var/log/rabbitmq/rabbit@$(hostname).log | grep -v "accepting AMQP\|user 'guest' authenticated" | cut -c1-400 | tail -12
sudo rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers
pkill -f sms-noack.py
sudo rabbitmqctl eval 'application:set_env(rabbit, consumer_timeout, 1800000).'
sudo rabbitmqctl purge_queue sms
echo "### DONE"
