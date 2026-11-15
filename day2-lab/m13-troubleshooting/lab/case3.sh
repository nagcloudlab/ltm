sed -i "s/^BUG = False/BUG = True/" /opt/notification.py; systemctl restart notification; sleep 3
: > /usr/local/kong/logs/access.log
for i in 1 2 3 4 5 6; do curl -s -X POST -H "apikey: demo-key-123" "localhost:8000/api/payment/transfer?to=%2B91980000000$i&amount=500"; echo; done
echo "== kong"; cat /usr/local/kong/logs/access.log
sleep 8
echo "== tomcat"; grep transfer /opt/tomcat/logs/localhost_access_log.2026-11-15.txt | tail -3; grep "published" /opt/tomcat/logs/localhost.2026-11-15.log | tail -3
echo "== queues"; rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers
echo "== notif"; tail -7 /var/log/notification/notification.log
echo "== systemctl"; systemctl status notification --no-pager | head -5
echo "== get"; rabbitmqadmin get queue=sms.dlq count=1 ackmode=ack_requeue_true
echo "== api"; curl -s -u guest:guest -X POST -H "content-type: application/json" -d '{"count":1,"ackmode":"ack_requeue_true","encoding":"auto"}' localhost:15672/api/queues/%2F/sms.dlq/get | jq '.[0] | {payload, headers: .properties.headers}'
