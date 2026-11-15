#!/bin/bash
r(){ echo; echo "\$ $*"; eval "$@" 2>&1; }
sudo rabbitmq-plugins enable rabbitmq_management >/dev/null 2>&1
for i in $(seq 1 90); do curl -s -o /dev/null localhost:15672/ && break; sleep 2; done
curl -s -o rabbitmqadmin http://localhost:15672/cli/rabbitmqadmin; chmod +x rabbitmqadmin; sudo mv rabbitmqadmin /usr/local/bin/
r rabbitmqadmin declare queue name=sms durable=true
r rabbitmqadmin declare exchange name=payments type=topic
r rabbitmqadmin declare binding source=payments destination=sms routing_key=payment.completed
r rabbitmqadmin publish exchange=payments routing_key=payment.completed payload="'{\"event\":\"PaymentCompleted\",\"paymentId\":\"PAY-1001\"}'"
r sudo rabbitmqctl list_queues name messages consumers
r rabbitmqadmin -f long get queue=sms ackmode=ack_requeue_true
r rabbitmqadmin -f long get queue=sms ackmode=ack_requeue_false
r rabbitmqadmin declare exchange name=payments.dlx type=fanout
r rabbitmqadmin declare queue name=sms.dlq durable=true
r rabbitmqadmin declare binding source=payments.dlx destination=sms.dlq
r sudo rabbitmqctl set_policy sms-dlx "'^sms\$'" "'{\"dead-letter-exchange\":\"payments.dlx\"}'" --apply-to queues
r rabbitmqadmin publish exchange=payments routing_key=payment.completed payload="'{\"event\":\"PaymentCompleted\",\"paymentId\":\"PAY-2002\"}'"
r rabbitmqadmin -f long get queue=sms ackmode=reject_requeue_true
r rabbitmqadmin -f long get queue=sms ackmode=reject_requeue_true
r rabbitmqadmin -f long get queue=sms ackmode=reject_requeue_false
r sudo rabbitmqctl list_queues name messages consumers
r "curl -s -u guest:guest -X POST http://localhost:15672/api/queues/%2F/sms.dlq/get -H 'content-type: application/json' -d '{\"count\":1,\"ackmode\":\"ack_requeue_true\",\"encoding\":\"auto\"}' | jq '.[0].properties.headers'"
r rabbitmqadmin publish exchange=payments routing_key=payment.completed payload="'{\"event\":\"PaymentCompleted\",\"paymentId\":\"PAY-3003\"}'" properties="'{\"expiration\":\"5000\"}'"
sleep 7
r "curl -s -u guest:guest -X POST http://localhost:15672/api/queues/%2F/sms.dlq/get -H 'content-type: application/json' -d '{\"count\":2,\"ackmode\":\"ack_requeue_true\",\"encoding\":\"auto\"}' | jq -c '.[] | [.payload, .properties.headers[\"x-death\"][0].reason]'"
r rabbitmqadmin publish exchange=payments routing_key=payment.complete payload=typo
echo ===DONE
