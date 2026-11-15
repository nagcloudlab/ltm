#!/usr/bin/env python3
# fails on one bad message and puts it back (requeue=True) for ever
import pika, json
conn=pika.BlockingConnection(pika.ConnectionParameters('localhost'))
ch=conn.channel(); ch.basic_qos(prefetch_count=1)
def on_msg(ch, m, props, body):
    try:
        d=json.loads(body); phone=d["phone"]
        ch.basic_ack(m.delivery_tag)
    except Exception as e:
        print("failed:", repr(e), "redelivered:", m.redelivered, flush=True)
        ch.basic_nack(m.delivery_tag, requeue=True)
ch.basic_consume('sms', on_msg)
ch.start_consuming()
