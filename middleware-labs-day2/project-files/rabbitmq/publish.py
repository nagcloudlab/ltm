#!/usr/bin/env python3
# publish.py - stands in for the payment service.
# Sends PaymentCompleted events to the exchange "payments".
#
# Usage:  python3 publish.py COUNT [ROUTING_KEY]
#   COUNT        how many events to send: P1, P2, P3 ...  (default 1)
#   ROUTING_KEY  the label the exchange routes on        (default payment.completed)
import json
import sys

import pika

count = int(sys.argv[1]) if len(sys.argv) > 1 else 1
key = sys.argv[2] if len(sys.argv) > 2 else "payment.completed"

# Connect to RabbitMQ on this laptop: port 5672, user guest/guest.
connection = pika.BlockingConnection(pika.ConnectionParameters("localhost"))
channel = connection.channel()

for i in range(1, count + 1):
    event = {"event": "PaymentCompleted", "id": f"P{i}", "amount": 500, "phone": "+91-98450-00000"}
    channel.basic_publish(
        exchange="payments",
        routing_key=key,
        body=json.dumps(event),
        properties=pika.BasicProperties(
            delivery_mode=2,                  # 2 = persistent: kept on disk, survives a restart
            content_type="application/json",
        ),
    )

connection.close()
# Note: "published" only means the exchange accepted the events.
# If no binding matches the key, RabbitMQ drops them and this script cannot tell.
print(f"published {count} event(s) to exchange 'payments' with key '{key}'")
