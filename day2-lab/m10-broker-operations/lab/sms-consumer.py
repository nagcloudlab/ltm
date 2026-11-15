#!/usr/bin/env python3
# the fixed SMS consumer: sends the SMS, then acks
import pika
conn=pika.BlockingConnection(pika.ConnectionParameters('localhost'))
ch=conn.channel(); ch.basic_qos(prefetch_count=10)
def on_msg(ch, m, props, body):
    print("SMS sent for", body.decode(), flush=True)
    ch.basic_ack(m.delivery_tag)
ch.basic_consume('sms', on_msg)
ch.start_consuming()
