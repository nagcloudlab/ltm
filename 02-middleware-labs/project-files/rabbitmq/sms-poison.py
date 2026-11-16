#!/usr/bin/env python3
# sms-poison.py - a notification-service with a BAD retry rule:
# when a message cannot be read it says "try again later" (nack with requeue=True).
# A broken message never gets better, so it comes back for ever. Ctrl+C to stop.
import json

import pika

connection = pika.BlockingConnection(pika.ConnectionParameters("localhost"))
channel = connection.channel()
channel.basic_qos(prefetch_count=1)

failures = 0


def on_message(ch, method, properties, body):
    global failures
    try:
        event = json.loads(body)
        phone = event["phone"]
        print(f"[poison] SMS sent for {event.get('id')} to {phone}", flush=True)
        ch.basic_ack(method.delivery_tag)
    except (ValueError, KeyError) as error:
        failures += 1
        if failures <= 3 or failures % 10000 == 0:      # print a few lines, not millions
            print(f"[poison] failed {failures} times: {error!r} redelivered={method.redelivered}", flush=True)
        ch.basic_nack(method.delivery_tag, requeue=True)  # BUG: puts it straight back


channel.basic_consume(queue="sms", on_message_callback=on_message)
print("[poison] waiting for messages on queue 'sms'. Ctrl+C to stop.", flush=True)
try:
    channel.start_consuming()
except KeyboardInterrupt:
    print(f"[poison] stopped after {failures} failures")
