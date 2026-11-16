#!/usr/bin/env python3
# sms-consumer.py - the GOOD notification-service: reads queue "sms",
# "sends" one SMS per PaymentCompleted event, then acknowledges (ack) it.
# A message it cannot read is rejected WITHOUT requeue (goes to dead letters).
#
# Usage:  python3 sms-consumer.py [NAME] [SECONDS_PER_MESSAGE] [PREFETCH]
#   NAME                 printed on every line, to tell two consumers apart (default sms-1)
#   SECONDS_PER_MESSAGE  pretend sending one SMS takes this long        (default 0)
#   PREFETCH             max messages handed to this consumer before it acks (default 10)
# Stop it with Ctrl+C.
import json
import sys
import time

import pika

name = sys.argv[1] if len(sys.argv) > 1 else "sms-1"
delay = float(sys.argv[2]) if len(sys.argv) > 2 else 0
prefetch = int(sys.argv[3]) if len(sys.argv) > 3 else 10

connection = pika.BlockingConnection(pika.ConnectionParameters("localhost"))
channel = connection.channel()
channel.basic_qos(prefetch_count=prefetch)


def on_message(ch, method, properties, body):
    again = " (redelivered)" if method.redelivered else ""
    try:
        event = json.loads(body)
        phone = event["phone"]
    except (ValueError, KeyError):
        # Bad message: retrying will never fix it. Reject, do not requeue.
        print(f"[{name}] bad message, rejected to dead letters: {body.decode()}", flush=True)
        ch.basic_reject(method.delivery_tag, requeue=False)
        return
    time.sleep(delay)                                 # "sending the SMS"
    print(f"[{name}] SMS sent for {event.get('id')} to {phone}{again}", flush=True)
    ch.basic_ack(method.delivery_tag)                 # done: RabbitMQ may delete it now


channel.basic_consume(queue="sms", on_message_callback=on_message)
print(f"[{name}] waiting for messages on queue 'sms' (prefetch {prefetch}). Ctrl+C to stop.", flush=True)
try:
    channel.start_consuming()
except KeyboardInterrupt:
    print(f"[{name}] stopped")
