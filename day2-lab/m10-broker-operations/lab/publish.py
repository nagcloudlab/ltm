#!/usr/bin/env python3
# publish.py N [routing_key] [body-prefix]
import sys, json, pika
n=int(sys.argv[1]); rk=sys.argv[2] if len(sys.argv)>2 else 'payment.completed'
conn=pika.BlockingConnection(pika.ConnectionParameters('localhost'))
ch=conn.channel()
for i in range(1,n+1):
    body=json.dumps({"event":"PaymentCompleted","id":f"P{i}","amount":500,"phone":"+91-98450-00000"})
    ch.basic_publish('payments', rk, body, pika.BasicProperties(delivery_mode=2, content_type='application/json'))
conn.close(); print(f"published {n} to exchange payments key {rk}")
