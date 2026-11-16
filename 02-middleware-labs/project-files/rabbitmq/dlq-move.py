#!/usr/bin/env python3
# dlq-move.py - moves messages from the dead-letter queue back to their work queue.
# Use it only AFTER the bug is fixed, or the messages fail again.
# It moves only the messages that are in the queue when it starts, so a message
# that fails again and comes back is NOT moved a second time.
#
# Usage:  python3 dlq-move.py [FROM_QUEUE] [TO_QUEUE]     (default sms.dlq -> sms)
import sys

import pika

source = sys.argv[1] if len(sys.argv) > 1 else "sms.dlq"
target = sys.argv[2] if len(sys.argv) > 2 else "sms"

connection = pika.BlockingConnection(pika.ConnectionParameters("localhost"))
channel = connection.channel()
channel.confirm_delivery()          # the broker confirms every publish before we go on

# passive=True: do not create anything, just ask how many messages are waiting
waiting = channel.queue_declare(queue=source, passive=True).method.message_count

moved = 0
while moved < waiting:
    method, properties, body = channel.basic_get(queue=source)   # take one message
    if method is None:                                            # queue emptied early
        break
    # "" = default exchange: delivers straight to the queue named by the routing key
    channel.basic_publish(exchange="", routing_key=target, body=body, properties=properties)
    channel.basic_ack(method.delivery_tag)                         # only now remove the original
    moved += 1

connection.close()
print(f"moved {moved} message(s) from {source} to {target}")
