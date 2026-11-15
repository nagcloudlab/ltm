#!/usr/bin/env python3
# notification-service: reads PaymentCompleted from queue sms, sends SMS
import json, logging, pika
logging.basicConfig(filename='/var/log/notification/notification.log', level=logging.INFO,
    format='%(asctime)s %(levelname)s [notification-service] %(message)s')
log = logging.getLogger()
BUG = True
def on_msg(ch, m, props, body):
    rid = (props.headers or {}).get('x-request-id')
    try:
        e = json.loads(body)
        phone = e['mobile'] if BUG else e['phone']
        log.info('SMS sent to %s for %s requestId=%s', phone, e['transferId'], rid)
        ch.basic_ack(m.delivery_tag)
    except Exception as ex:
        log.error('cannot send SMS requestId=%s: %s: %s -> rejected (requeue=false)', rid, type(ex).__name__, ex)
        ch.basic_reject(m.delivery_tag, requeue=False)
c = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
ch = c.channel(); ch.basic_qos(prefetch_count=10)
ch.basic_consume('sms', on_msg)
log.info('started, consuming queue sms')
ch.start_consuming()
