#!/bin/bash
cd /home/student/lab
rabbitmqadmin declare exchange name=quiz type=topic
for b in "payment.#" "payment.completed" "*.failed"; do
  q="q-$(echo $b | tr '.#*' '_hs')"; rabbitmqadmin declare queue name=$q >/dev/null
  rabbitmqadmin declare exchange name="quiz-$q" type=topic >/dev/null
  rabbitmqadmin declare binding source="quiz-$q" destination=$q routing_key="$b" >/dev/null
  for k in payment.completed payment payment.completed.sms payment.failed payment.card.failed; do
    echo "binding=$b key=$k: $(rabbitmqadmin publish exchange=quiz-$q routing_key=$k payload=x)"
  done
done
echo "### wrong exchange"
rabbitmqadmin publish exchange=paymnts routing_key=payment.completed payload=x
echo "### redeclare different args"
rabbitmqadmin declare queue name=sms durable=true
echo "### no sudo"
rabbitmqctl list_queues 2>&1 | head -8
echo "### cleanup"
for q in $(rabbitmqadmin -f bash list queues name); do case $q in q-*) rabbitmqadmin delete queue name=$q;; esac; done
for e in $(rabbitmqadmin -f bash list exchanges name); do case $e in quiz*) rabbitmqadmin delete exchange name=$e;; esac; done
echo DONE
