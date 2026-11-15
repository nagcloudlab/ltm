#!/usr/bin/env python3
# bug: rejects every message without requeue -> dead-lettered
import pika
conn=pika.BlockingConnection(pika.ConnectionParameters('localhost'))
ch=conn.channel(); ch.basic_qos(prefetch_count=50)
def on_msg(ch, m, props, body):
    ch.basic_reject(m.delivery_tag, requeue=False)
ch.basic_consume('sms', on_msg)
ch.start_consuming()
