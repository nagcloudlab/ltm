#!/usr/bin/env python3
# a buggy SMS consumer: takes messages, never acks
import pika, time
conn=pika.BlockingConnection(pika.ConnectionParameters('localhost'))
ch=conn.channel(); ch.basic_qos(prefetch_count=10)
def on_msg(ch, m, props, body):
    print("got", body.decode(), flush=True)   # ...forgot ch.basic_ack()
ch.basic_consume('sms', on_msg)
ch.start_consuming()
