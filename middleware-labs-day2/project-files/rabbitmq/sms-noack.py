#!/usr/bin/env python3
# sms-noack.py - a BUGGY notification-service: takes messages but never acks them.
# RabbitMQ keeps every message it handed out as "unacknowledged" until this
# consumer acks or disconnects. Stop it with Ctrl+C.
import pika

connection = pika.BlockingConnection(pika.ConnectionParameters("localhost"))
channel = connection.channel()
channel.basic_qos(prefetch_count=10)   # at most 10 un-acked messages at a time


def on_message(ch, method, properties, body):
    print("got", body.decode(), flush=True)
    # BUG: forgot ch.basic_ack(method.delivery_tag)


channel.basic_consume(queue="sms", on_message_callback=on_message)
print("[noack] waiting for messages on queue 'sms'. Ctrl+C to stop.", flush=True)
try:
    channel.start_consuming()
except KeyboardInterrupt:
    print("[noack] stopped")
