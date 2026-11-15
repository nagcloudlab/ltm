#!/usr/bin/env python3
# sms-rejectall.py - a BUGGY release of the notification-service:
# rejects EVERY message without requeue. With the sms-dlx policy in place,
# each rejected message goes to the dead-letter queue sms.dlq. Ctrl+C to stop.
import pika

connection = pika.BlockingConnection(pika.ConnectionParameters("localhost"))
channel = connection.channel()
channel.basic_qos(prefetch_count=50)

count = 0


def on_message(ch, method, properties, body):
    global count
    count += 1
    ch.basic_reject(method.delivery_tag, requeue=False)   # BUG: "cannot process" for everything
    if count % 10 == 0:
        print(f"[rejectall] rejected {count} messages so far", flush=True)


channel.basic_consume(queue="sms", on_message_callback=on_message)
print("[rejectall] waiting for messages on queue 'sms'. Ctrl+C to stop.", flush=True)
try:
    channel.start_consuming()
except KeyboardInterrupt:
    print(f"[rejectall] stopped after rejecting {count} messages")
