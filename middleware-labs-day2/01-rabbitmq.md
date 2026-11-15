# Lab 1 — Payment events with RabbitMQ

- **Needs:** the Day 1 labs finished and [Day 2 start](00-day2-start.md) checked; internet access for Ubuntu packages
- **You build:** a RabbitMQ broker that carries **PaymentCompleted** events from the payment service to an SMS service and a fraud-check service, with retries, dead letters, monitoring and recovery

```text
publish.py (payment service)
   |
   v
exchange "payments" (topic)
   |-- key payment.completed --> queue sms   --> sms-consumer.py (notification-service)
   |-- key payment.#         --> queue fraud --> (fraud-check service)

queue sms: rejected or expired messages --> exchange payments.dlx (fanout) --> queue sms.dlq
```

- RabbitMQ runs as a native Ubuntu service. Small Python scripts stand in for the services; you do not write code.
- Keep **three terminals** open: **T1** for commands, **T2** and **T3** for consumers. Stop a consumer with **Ctrl+C**.

## 1. Why a broker

- Without a broker, the payment service calls the SMS gateway directly. If SMS is slow or down, the payment waits or fails — for a reason that has nothing to do with money.
- With a broker, the payment service hands the event to RabbitMQ and is done. RabbitMQ keeps it until the SMS service is ready.
- **Producer** → **broker** → **consumer**. The producer does not know who reads the event, or whether the reader is running right now.

| Word | Meaning in this lab |
| --- | --- |
| Producer | `publish.py` — sends PaymentCompleted events |
| Exchange | `payments` — the sorting desk; never stores messages |
| Routing key | label on each message, e.g. `payment.completed` |
| Binding | rule "exchange → queue for keys like X" |
| Queue | `sms`, `fraud` — where messages wait, in order |
| Consumer | `sms-consumer.py` — reads a queue and **acks** each message when done |

## 2. Install RabbitMQ

- Ubuntu 24.04 ships RabbitMQ 3.12.1. `python3-pika` (the Python client used by the scripts) and `jq` came with [Day 2 start](00-day2-start.md).

Refresh the package lists:

```bash
sudo apt update
```

Install the broker:

```bash
sudo apt install -y rabbitmq-server
```

Check the installed versions:

```bash
dpkg -l rabbitmq-server python3-pika | tail -n 2
```

- **Expected:**

```text
ii  python3-pika    1.2.0-1           all          AMQP client library for Python 3
ii  rabbitmq-server 3.12.1-1ubuntu1.7 all          AMQP server written in Erlang
```

Check the service:

```bash
systemctl is-active rabbitmq-server
```

Check that it starts at boot:

```bash
systemctl is-enabled rabbitmq-server
```

- **Expected:** `active` and `enabled` — the package starts the broker for you.

## 3. Prove the broker is running

- A running service is not enough: check the process, the ports and the broker's own health answer.

Show the broker process:

```bash
ps -C beam.smp -o user,pid,comm
```

- **Expected:** one `beam.smp` process owned by user `rabbitmq`. RabbitMQ is written in Erlang; `beam.smp` is the Erlang virtual machine.

Show the listening ports:

```bash
sudo ss -lntp | grep -E ':(5672|15672|25672|4369) '
```

- Sample output:

```text
LISTEN 0      128          0.0.0.0:25672      0.0.0.0:*    users:(("beam.smp",pid=1875,fd=18))
LISTEN 0      128                *:5672             *:*    users:(("beam.smp",pid=1875,fd=35))
LISTEN 0      4096               *:4369             *:*    users:(("epmd",pid=1755,fd=3),("systemd",pid=1,fd=82))
```

| Port | Who listens | Used by |
| --- | --- | --- |
| 5672 | `beam.smp` | AMQP — producers and consumers |
| 25672 | `beam.smp` | CLI tools and other cluster nodes |
| 4369 | `epmd` | Erlang "port directory": tells tools where the node is |
| 15672 | `beam.smp` | Web UI and HTTP API — appears in step 4 |

Ask the broker if it answers:

```bash
sudo rabbitmq-diagnostics ping
```

- **Expected:** `Ping succeeded`.

Show the first lines of the status report:

```bash
sudo rabbitmq-diagnostics status | head -n 12
```

- **Expected:** `RabbitMQ version: 3.12.1` and `Node name: rabbit@<your-hostname>`.

Try the admin tool without sudo:

```bash
rabbitmqctl list_users
```

- **Expected:** a long usage text ending with `Only root or rabbitmq should run rabbitmqctl`.
- **Why:** `rabbitmqctl` proves who you are with a secret file (the Erlang cookie) readable only by root and `rabbitmq`. Always use `sudo rabbitmqctl`.

List the users with sudo:

```bash
sudo rabbitmqctl list_users
```

List the virtual hosts:

```bash
sudo rabbitmqctl list_vhosts
```

- **Expected:** user `guest` with tag `[administrator]`; one virtual host `/`.

Read the end of the broker log:

```bash
sudo tail -n 5 /var/log/rabbitmq/rabbit@$(hostname -s).log
```

- Sample lines (the failed no-sudo attempt is logged too):

```text
2026-11-15 08:07:53.483477+00:00 [info] <0.615.0> Server startup complete; 0 plugins started.
2026-11-15 08:08:00.981532+00:00 [error] <0.646.0> ** Connection attempt from node 'rabbit_ctl_11@lab-laptop' rejected. Invalid challenge reply. **
```

- **If it fails:** `sudo journalctl -u rabbitmq-server -n 30` shows why the service did not start. A hostname that does not resolve (missing from `/etc/hosts`) is the usual cause.

## 4. Management UI and rabbitmqadmin

- The management plugin adds a web UI, an HTTP API and the `rabbitmqadmin` command-line tool.

Enable the plugin:

```bash
sudo rabbitmq-plugins enable rabbitmq_management
```

- **Expected:** `started 3 plugins.` (`rabbitmq_management`, `rabbitmq_management_agent`, `rabbitmq_web_dispatch`). No restart needed.

Check port 15672:

```bash
sudo ss -lntp | grep ':15672 '
```

Check the UI answers:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:15672/
```

- **Expected:** `200`.
- Open **http://localhost:15672** in Firefox on the laptop and log in as `guest` / `guest`. Look at the tabs: **Overview, Connections, Channels, Exchanges, Queues and Streams, Admin**.

Call the HTTP API as guest from localhost:

```bash
curl -s -u guest:guest http://localhost:15672/api/overview | jq '{rabbitmq_version, node}'
```

Call it again through the laptop's network address:

```bash
curl -s -u guest:guest http://$(hostname -I | awk '{print $1}'):15672/api/overview; echo
```

- **Expected:** the first call shows `"rabbitmq_version": "3.12.1"`; the second is refused:

```text
{"error":"not_authorised","reason":"User can only log in via localhost"}
```

- **Why:** `guest` is a well-known password, so RabbitMQ only accepts it from the same machine. Real systems create their own users.

Download `rabbitmqadmin` from the broker:

```bash
curl -s -o /tmp/rabbitmqadmin http://localhost:15672/cli/rabbitmqadmin
```

Install it:

```bash
sudo install -m 755 /tmp/rabbitmqadmin /usr/local/bin/rabbitmqadmin
```

Check it:

```bash
rabbitmqadmin --version
```

- **Expected:** `rabbitmqadmin 3.12.1`. It talks to port 15672 as `guest`, so it needs no sudo.

## 5. First message by hand

- Build the smallest path: exchange `payments` → binding `payment.completed` → queue `sms`.

Create the exchange (type **topic**, survives a restart):

```bash
rabbitmqadmin declare exchange name=payments type=topic durable=true
```

Create the queue (durable):

```bash
rabbitmqadmin declare queue name=sms durable=true
```

Bind the queue to the exchange:

```bash
rabbitmqadmin declare binding source=payments destination=sms routing_key=payment.completed
```

- **Expected:** `exchange declared`, `queue declared`, `binding declared`.

List the bindings:

```bash
sudo rabbitmqctl -q list_bindings source_name destination_name routing_key
```

- **Expected:** `payments  sms  payment.completed`. The extra line with an empty source is the built-in default exchange: every queue is bound to it by its own name. `-q` (quiet) hides the banner lines.

Publish one PaymentCompleted event:

```bash
rabbitmqadmin publish exchange=payments routing_key=payment.completed payload='{"event":"PaymentCompleted","id":"P1001","amount":500,"phone":"+91-98450-00000"}'
```

Count the messages in each queue:

```bash
sudo rabbitmqctl -q list_queues name messages
```

- **Expected:** `Message published`, then `sms  1`.

Peek at the message and put it back:

```bash
rabbitmqadmin -f long get queue=sms ackmode=ack_requeue_true
```

Take the message (ack, do not put back):

```bash
rabbitmqadmin -f long get queue=sms ackmode=ack_requeue_false
```

Try once more:

```bash
rabbitmqadmin get queue=sms
```

- **Expected:** both gets show the payload; the second one shows `redelivered: True` (it was handed out once already); the last says `No items`.
- In the UI open **Queues and Streams → sms → Get messages** to do the same with buttons.

## 6. Python producer and consumer

- Copy the scripts once, then always work in `~/lab/rabbitmq`.

Create the work folder:

```bash
mkdir -p ~/lab/rabbitmq
```

Copy the scripts:

```bash
cp ~/ltm/middleware-labs-day2/project-files/rabbitmq/*.py ~/lab/rabbitmq/
```

Go there (do this in **every** new terminal):

```bash
cd ~/lab/rabbitmq
```

Read the producer:

```bash
cat publish.py
```

- It connects to `localhost:5672`, publishes `COUNT` events `P1, P2, …` to exchange `payments` and marks each one **persistent** (`delivery_mode=2`).

Publish 10 events:

```bash
python3 publish.py 10
```

Count them:

```bash
sudo rabbitmqctl -q list_queues name messages consumers
```

- **Expected:** `published 10 event(s) …` and `sms  10  0` — ten waiting, nobody reading.

Read the consumer:

```bash
cat sms-consumer.py
```

**T2** — start the SMS consumer:

```bash
cd ~/lab/rabbitmq && python3 sms-consumer.py
```

- **Expected:** the messages come out in the order they went in (**FIFO** — first in, first out):

```text
[sms-1] waiting for messages on queue 'sms' (prefetch 10). Ctrl+C to stop.
[sms-1] SMS sent for P1 to +91-98450-00000
[sms-1] SMS sent for P2 to +91-98450-00000
...
[sms-1] SMS sent for P10 to +91-98450-00000
```

**T1** — check the queue while the consumer waits:

```bash
sudo rabbitmqctl -q list_queues name messages consumers
```

- **Expected:** `sms  0  1` — empty queue, one consumer attached.
- Publish 3 more from T1 (`python3 publish.py 3`) and watch them appear in T2 at once. Then press **Ctrl+C** in T2.

## 7. Topic routing: one event, two queues

- The fraud-check service also wants payment events — **all** of them, not only completed ones. Topic bindings use `*` (exactly one word) and `#` (zero or more words).

Create the fraud queue:

```bash
rabbitmqadmin declare queue name=fraud durable=true
```

Bind it with `payment.#`:

```bash
rabbitmqadmin declare binding source=payments destination=fraud routing_key='payment.#'
```

List the bindings:

```bash
sudo rabbitmqctl -q list_bindings source_name destination_name routing_key
```

- **Expected:** `payments  fraud  payment.#` and `payments  sms  payment.completed`.

Publish one completed payment:

```bash
python3 publish.py 1
```

Count:

```bash
sudo rabbitmqctl -q list_queues name messages
```

- **Expected:** `fraud  1` and `sms  1` — **one** publish, **two** copies.

Publish one failed payment:

```bash
python3 publish.py 1 payment.failed
```

Count again:

```bash
sudo rabbitmqctl -q list_queues name messages
```

- **Expected:** `fraud  2`, `sms  1` — only `payment.#` matches `payment.failed`.

Publish with a typo in the key:

```bash
python3 publish.py 1 paymnet.completed
```

Count again:

```bash
sudo rabbitmqctl -q list_queues name messages
```

- **Expected:** the script says `published 1 event(s) … 'paymnet.completed'`, but the counts do not change. The event is **gone**: no binding matched, so the exchange dropped it.

Publish the same typo with rabbitmqadmin:

```bash
rabbitmqadmin publish exchange=payments routing_key=paymnet.completed payload=test
```

- **Expected:** `Message published but NOT routed` — rabbitmqadmin asks the broker to report unroutable messages; our simple producer does not.

Publish to an exchange name with a typo:

```bash
rabbitmqadmin publish exchange=paymnts routing_key=payment.completed payload=test
```

- **Expected:** `*** 404 NOT_FOUND - no exchange 'paymnts' in vhost '/'` — a wrong exchange is an error; a wrong key is silent.

| Routing key | sms (`payment.completed`) | fraud (`payment.#`) |
| --- | --- | --- |
| `payment.completed` | yes | yes |
| `payment.failed` | no | yes |
| `payment.complete` (typo) | no | yes |
| `paymnet.completed` (typo) | no | no — NOT routed |

Empty both queues before the next step (test messages only):

```bash
sudo rabbitmqctl purge_queue sms
```

```bash
sudo rabbitmqctl purge_queue fraud
```

- **From now on** every `payment.completed` event also lands in `fraud`, and no service reads it yet. Expect its count to keep growing; you clean it in step 13.

## 8. Work queue: two consumers share one queue

- One SMS consumer is too slow at peak time. Start a second copy on the same queue: RabbitMQ hands messages out in turn (**round robin**).

**T2** — first consumer:

```bash
cd ~/lab/rabbitmq && python3 sms-consumer.py sms-1
```

**T3** — second consumer:

```bash
cd ~/lab/rabbitmq && python3 sms-consumer.py sms-2
```

**T1** — list the consumers:

```bash
sudo rabbitmqctl -q list_consumers queue_name ack_required prefetch_count
```

- **Expected:** two lines `sms  true  10`.

Publish 10 events:

```bash
python3 publish.py 10
```

- **Expected:** T2 and T3 each print five lines, alternating, e.g. T2 gets P2, P4, P6, P8, P10 and T3 gets P1, P3, P5, P7, P9.
- **Why:** order is kept **inside the queue**, but two consumers work in parallel, so the SMS for P2 can go out before P1. Need strict order? Use one consumer.
- Press **Ctrl+C** in T2 and T3.

### Prefetch: how many messages a consumer may hold

- **Prefetch** = how many unacknowledged messages RabbitMQ may hand to one consumer at a time. The script's arguments are `NAME SECONDS_PER_MESSAGE PREFETCH`.

**T2** — a slow consumer (1 second per SMS), prefetch 10:

```bash
python3 sms-consumer.py slow 1 10
```

**T3** — a fast consumer, prefetch 10:

```bash
python3 sms-consumer.py fast 0 10
```

**T1** — publish 20 events:

```bash
python3 publish.py 20
```

Look at the queue within a few seconds:

```bash
sudo rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers
```

- **Expected:** `sms  0  <some>  2` — nothing waiting, but several messages **unacknowledged**: they sit inside the slow consumer. Counted at the end, slow and fast each sent **10** SMS; the fast one sat idle while the slow one worked through its share.
- Press **Ctrl+C** in T2 and T3, then repeat with prefetch 1.

**T2** — slow, prefetch 1:

```bash
python3 sms-consumer.py slow 1 1
```

**T3** — fast, prefetch 1:

```bash
python3 sms-consumer.py fast 0 1
```

**T1** — publish 20 events:

```bash
python3 publish.py 20
```

- **Expected:** fast sends about **19** SMS, slow about **1** (tested: 19 and 1). With prefetch 1 a busy consumer gets no new message until it acks.
- **Why:** a small prefetch spreads work fairly; a large prefetch is faster per consumer but can pile work on a slow one.
- Press **Ctrl+C** in T2 and T3.

## 9. Acknowledgements: a consumer that never acks

- RabbitMQ deletes a message only when the consumer **acks** it. A message handed out but not acked is **unacknowledged**: kept, but not given to anyone else.

Read the buggy consumer:

```bash
cat sms-noack.py
```

**T1** — publish 20 events:

```bash
python3 publish.py 20
```

**T2** — start the buggy consumer:

```bash
python3 sms-noack.py
```

**T1** — look at the queue:

```bash
sudo rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers
```

Look at the consumer's channel:

```bash
sudo rabbitmqctl -q list_channels name messages_unacknowledged prefetch_count
```

- **Expected:**

```text
name	messages_ready	messages_unacknowledged	consumers
sms	10	10	1
```

```text
name	messages_unacknowledged	prefetch_count
127.0.0.1:42104 -> 127.0.0.1:5672 (1)	10	10
```

- T2 printed 10 `got …` lines and then nothing: it holds its full prefetch (10) and never acks, so the other 10 wait for ever. Run the `list_queues` command again after a minute — the numbers do not move. This is a **stuck consumer**.
- Press **Ctrl+C** in T2 (the consumer disconnects).

Look again:

```bash
sudo rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers
```

- **Expected:** `sms  20  0  0` — the 10 unacknowledged messages went back to the queue. Nothing was lost.

**T2** — start the good consumer:

```bash
python3 sms-consumer.py
```

- **Expected:** P1–P10 print with ` (redelivered)` — they were handed out once already; P11–P20 print without it. A redelivered message may have been half-processed, so real consumers must be safe to run twice (**idempotent**: do not send the same SMS twice).
- Press **Ctrl+C** in T2.
- RabbitMQ 3.12 closes a consumer that keeps a message unacknowledged for more than 30 minutes (`consumer_timeout`, 1800000 ms); its messages then return to the queue.

## 10. Retry and dead letters

- A message that cannot be processed must not vanish and must not block the queue. A **dead-letter exchange** catches messages that are **rejected** (without requeue) or **expire**.
- Here: policy `sms-dlx` tells queue `sms` to send its dead letters to exchange `payments.dlx` (type **fanout**: copies to every bound queue, ignores the key) → queue `sms.dlq`.

Create the dead-letter exchange:

```bash
rabbitmqadmin declare exchange name=payments.dlx type=fanout durable=true
```

Create the dead-letter queue:

```bash
rabbitmqadmin declare queue name=sms.dlq durable=true
```

Bind them:

```bash
rabbitmqadmin declare binding source=payments.dlx destination=sms.dlq
```

Attach the policy to queue `sms`:

```bash
sudo rabbitmqctl set_policy sms-dlx '^sms$' '{"dead-letter-exchange":"payments.dlx"}' --apply-to queues
```

List the policies:

```bash
sudo rabbitmqctl -q list_policies
```

Show which queue uses it:

```bash
sudo rabbitmqctl -q list_queues name policy messages
```

- **Expected:** policy `sms-dlx` with pattern `^sms$`; queue `sms` shows `sms-dlx` in the policy column, `sms.dlq` and `fraud` show nothing.
- **Why a policy:** it can be added or changed on a running queue. The alternative, a queue argument `x-dead-letter-exchange`, is fixed when the queue is created.

Publish one event:

```bash
python3 publish.py 1
```

Reject it **with** requeue (a retry):

```bash
rabbitmqadmin -f long get queue=sms ackmode=reject_requeue_true
```

Reject it **without** requeue (give up):

```bash
rabbitmqadmin -f long get queue=sms ackmode=reject_requeue_false
```

Count:

```bash
sudo rabbitmqctl -q list_queues name messages
```

- **Expected:** after the first get the message is still in `sms`; after the second, `sms  0` and `sms.dlq  1`.

Read why it died (the `x-death` header RabbitMQ added):

```bash
rabbitmqadmin -f pretty_json get queue=sms.dlq ackmode=ack_requeue_true | jq '.[0].properties.headers'
```

- **Expected:**

```text
{
  "x-death": [
    {
      "count": 1,
      "exchange": "payments",
      "queue": "sms",
      "reason": "rejected",
      "routing-keys": [
        "payment.completed"
      ],
      "time": 1794730231
    }
  ],
  "x-first-death-exchange": "payments",
  "x-first-death-queue": "sms",
  "x-first-death-reason": "rejected"
}
```

- `x-death` tells you the original queue, the original routing key, the reason and how many times it died. `time` is Unix seconds.

### A buggy release rejects everything

Read it:

```bash
cat sms-rejectall.py
```

**T2** — start it:

```bash
python3 sms-rejectall.py
```

**T1** — publish 5 events:

```bash
python3 publish.py 5
```

Count:

```bash
sudo rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers
```

- **Expected:** `sms  0  0  1` and `sms.dlq  6  0  0` — the 5 new events went straight to dead letters. No SMS was sent, but no event was lost either.
- Press **Ctrl+C** in T2.

### Expired messages are dead-lettered too

Publish an event that may wait at most 10 seconds (`expiration` is in milliseconds):

```bash
rabbitmqadmin publish exchange=payments routing_key=payment.completed payload='{"event":"PaymentCompleted","id":"P2002","amount":500,"phone":"+91-98450-00000"}' properties='{"expiration":"10000"}'
```

Count now:

```bash
sudo rabbitmqctl -q list_queues name messages
```

Wait, then count again:

```bash
sleep 11; sudo rabbitmqctl -q list_queues name messages
```

- **Expected:** first `sms  1`, then `sms  0` and `sms.dlq  7` — nobody consumed it in time.

Show each dead letter with its reason:

```bash
rabbitmqadmin -f pretty_json get queue=sms.dlq count=10 ackmode=ack_requeue_true | jq -r '.[] | .payload + "  reason=" + .properties.headers["x-first-death-reason"]'
```

- **Expected:** six lines ending `reason=rejected`, the last one (P2002) ending `reason=expired`.

Empty the dead-letter queue (test messages only):

```bash
sudo rabbitmqctl purge_queue sms.dlq
```

## 11. A poison message

- A **poison message** can never be processed (here: no `phone` field). If the consumer answers "try again" (`requeue=True`), RabbitMQ puts it straight back at the head of the queue — for ever.

Publish a broken event (no phone number):

```bash
rabbitmqadmin publish exchange=payments routing_key=payment.completed payload='{"event":"PaymentCompleted","id":"P3003","amount":500}'
```

Read the consumer with the bad retry rule:

```bash
cat sms-poison.py
```

**T2** — start it:

```bash
python3 sms-poison.py
```

- **Expected:** it fails thousands of times per second (it prints only every 10000th failure):

```text
[poison] failed 1 times: KeyError('phone') redelivered=False
[poison] failed 2 times: KeyError('phone') redelivered=True
[poison] failed 3 times: KeyError('phone') redelivered=True
[poison] failed 10000 times: KeyError('phone') redelivered=True
[poison] failed 20000 times: KeyError('phone') redelivered=True
```

**T1** — wait 10 seconds, then read the redelivery rate:

```bash
rabbitmqadmin list queues name messages messages_unacknowledged message_stats.redeliver_details.rate
```

- Sample output:

```text
| sms     | 1        | 1                       | 13601.0                              |
```

- One message, redelivered about 13,600 times per second (yours will differ): CPU burns, the log of a real service fills, and with prefetch 1 every message behind it waits.
- Press **Ctrl+C** in T2 (`[poison] stopped after … failures`). The message is still in `sms`.

**T2** — start the good consumer instead:

```bash
python3 sms-consumer.py
```

- **Expected:** `[sms-1] bad message, rejected to dead letters: {"event":"PaymentCompleted","id":"P3003","amount":500}` — one try, then `requeue=False`.
- Press **Ctrl+C** in T2.

**T1** — check where it went:

```bash
sudo rabbitmqctl -q list_queues name messages
```

- **Expected:** `sms  0`, `sms.dlq  1` — the poison message is parked; the queue flows again.

| Consumer answer | Effect | Use for |
| --- | --- | --- |
| `ack` | deleted — done | success |
| `nack`/`reject`, `requeue=True` | back to the queue, immediately | short glitches only — loops on a bad message |
| `nack`/`reject`, `requeue=False` | dead-lettered (dropped if no DLX) | bad data that will never succeed |

- Leave the poison message in `sms.dlq`; you meet it again in step 13.

## 12. Monitoring the broker

- Four numbers per queue tell you almost everything.

List the queues with the key columns:

```bash
sudo rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers
```

| Column | Healthy | Trouble |
| --- | --- | --- |
| `messages_ready` | small, going down | growing → consumers too slow or none |
| `messages_unacknowledged` | ≤ consumers × prefetch, changing | stuck at the same number → consumer hangs or never acks |
| `consumers` | what you expect (1, 2 …) | `0` on a queue that should be read |
| `sms.dlq` messages | 0 | growing → a consumer is rejecting |

List the exchanges:

```bash
sudo rabbitmqctl -q list_exchanges name type durable
```

List the bindings:

```bash
sudo rabbitmqctl -q list_bindings source_name destination_name routing_key
```

List the consumers:

```bash
sudo rabbitmqctl -q list_consumers queue_name ack_required prefetch_count
```

List the client connections:

```bash
sudo rabbitmqctl -q list_connections user peer_host state
```

- **Expected:** exchanges `payments  topic  true` and `payments.dlx  fanout  true` (the `amq.*` ones are built in); bindings for `sms`, `fraud`, `sms.dlq`; no consumers or connections while all scripts are stopped.
- In the UI, open **Queues and Streams**: the columns **Ready**, **Unacked**, **Total** and the **incoming / deliver / ack** rates are the same numbers. Click `sms` to see its graphs, consumers and the `sms-dlx` policy.
- The UI and `rabbitmqadmin` refresh their statistics about every 5 seconds; `rabbitmqctl` reads live values.

### Memory and disk alarms

- When RabbitMQ runs low on memory or disk it raises an **alarm** and **blocks every publisher** until it clears. Consumers keep working.

Show the alarm limits and current values:

```bash
sudo rabbitmq-diagnostics status | grep -E 'watermark|Free disk'
```

- Sample output:

```text
Memory high watermark setting: 0.4 of available memory, computed to: 3.3269 gb
Low free disk space watermark: 0.05 gb
Free disk space: 871.2314 gb
```

Show the configured values:

```bash
sudo rabbitmqctl environment | grep -E 'vm_memory_high_watermark|disk_free_limit|consumer_timeout'
```

- **Expected:** `{vm_memory_high_watermark,0.4}` (40 % of RAM), `{disk_free_limit,50000000}` (50 MB free), `{consumer_timeout,1800000}` (30 min).

Check for alarms:

```bash
sudo rabbitmq-diagnostics alarms
```

Check for local alarms (exit code for scripts):

```bash
sudo rabbitmq-diagnostics check_local_alarms; echo "exit=$?"
```

Check that every listener accepts connections:

```bash
sudo rabbitmq-diagnostics check_port_connectivity
```

- **Expected:** `reported no alarms`, `exit=0`, `Successfully connected to ports 5672, 15672, 25672 …`.

Read the connection lines in the log:

```bash
sudo grep -E 'accepting AMQP|closing AMQP' /var/log/rabbitmq/rabbit@$(hostname -s).log | tail -n 4
```

- Sample lines:

```text
2026-11-15 08:27:07.829644+00:00 [info] <0.724.0> accepting AMQP connection <0.724.0> (127.0.0.1:52362 -> 127.0.0.1:5672)
2026-11-15 08:27:07.833055+00:00 [info] <0.724.0> closing AMQP connection <0.724.0> (127.0.0.1:52362 -> 127.0.0.1:5672, vhost: '/', user: 'guest')
```

- Log times are UTC (`+00:00`). Save the queue view as evidence:

```bash
sudo rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers | tee ~/lab/evidence/day2/lab1-queues.txt
```

## 13. Fault exercises

### 13.1 Stuck queue — the consumer stopped

**Break** — **T2**, start the consumer:

```bash
python3 sms-consumer.py
```

**T1** — publish 5 (they are sent at once):

```bash
python3 publish.py 5
```

- Now press **Ctrl+C** in T2 — the notification-service "crashed".

**T1** — payments keep coming:

```bash
python3 publish.py 50
```

**Observe** — look at the queue:

```bash
sudo rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers
```

Publish more and look again:

```bash
python3 publish.py 50; sudo rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers
```

- **Expected:** `sms  50  0  0`, then `sms  100  0  0` — ready grows, **consumers 0**. Payments still succeed; only SMS are late. The fix is on the consumer side, not in RabbitMQ.

**Recover** — **T2**, start the consumer:

```bash
python3 sms-consumer.py
```

**Verify** — **T1**:

```bash
sudo rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers
```

- **Expected:** T2 prints 100 SMS lines (P1–P50 twice); `sms  0  0  1`. Nothing was lost while the consumer was down.
- Press **Ctrl+C** in T2 before 13.2.

### 13.2 DLQ flood — a buggy release

**Break** — **T2**, deploy the "new release":

```bash
python3 sms-rejectall.py
```

**T1** — normal traffic:

```bash
python3 publish.py 100
```

**Observe**:

```bash
sudo rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers
```

Read one dead letter:

```bash
rabbitmqadmin -f pretty_json get queue=sms.dlq ackmode=ack_requeue_true | jq '.[0].properties.headers["x-death"][0] | {queue, reason, count}'
```

- **Expected:** `sms  0  0  1` but `sms.dlq  101  0  0` (100 new + the poison message from step 11). The consumer is connected and "working", yet nothing is sent: the DLQ count is the alarm. The first dead letter is the poison message with `"reason": "rejected"`.

**Recover** — stop the buggy release: press **Ctrl+C** in T2. Then **T2**, roll back to the good consumer:

```bash
python3 sms-consumer.py
```

**T1** — read the mover script:

```bash
cat dlq-move.py
```

Move the dead letters back to `sms`:

```bash
python3 dlq-move.py
```

- **Expected:** `moved 101 message(s) from sms.dlq to sms`; T2 prints 100 SMS lines and one `bad message, rejected to dead letters` — the poison message fails again and returns to the DLQ.
- **Why move only after the fix:** moving while the bug is live just fills the DLQ again. The script moves only what was there when it started, so a message that fails again is not looped.

**Verify**:

```bash
sudo rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers
```

- **Expected:** `sms  0  0  1`, `sms.dlq  1  0  0` — only the real poison message remains, for a human to look at.
- Press **Ctrl+C** in T2.

#### Optional — the same move with the shovel plugin

- A **shovel** is RabbitMQ's built-in mover. With `src-delete-after: queue-length` it moves the messages present at the start, then deletes itself (tested on 3.12.1 with the same result as the script).

Enable the shovel plugins:

```bash
sudo rabbitmq-plugins enable rabbitmq_shovel rabbitmq_shovel_management
```

Run a one-time shovel from `sms.dlq` to `sms` (with the good consumer running in T2):

```bash
sudo rabbitmqctl set_parameter shovel dlq-replay '{"src-uri":"amqp://","src-queue":"sms.dlq","dest-uri":"amqp://","dest-queue":"sms","src-delete-after":"queue-length"}'
```

Check that it finished and removed itself:

```bash
sudo rabbitmqctl -q list_parameters
```

- **Expected:** `list_parameters` prints nothing once the move is done. In the UI: **Admin → Shovel Status**.

### 13.3 Purge with care

- `purge_queue` deletes every message in a queue. There is no undo, and persistent messages are deleted from disk too. Look before you purge, and keep a copy of anything a human must still see.

Save the poison message as evidence:

```bash
rabbitmqadmin -f pretty_json get queue=sms.dlq ackmode=ack_requeue_true | tee ~/lab/evidence/day2/lab1-poison-message.json
```

Purge the dead-letter queue:

```bash
sudo rabbitmqctl purge_queue sms.dlq
```

Count `fraud` (nobody reads it in this lab):

```bash
sudo rabbitmqctl -q list_queues name messages
```

Purge it:

```bash
sudo rabbitmqctl purge_queue fraud
```

- **Expected:** `fraud` had a few hundred messages — a queue without a consumer grows for ever and fills disk. After purging, both show `0`.

### 13.4 Disk alarm — publishers blocked

**Break** — pretend the disk is nearly full (require 5000 GB free):

```bash
sudo rabbitmqctl set_disk_free_limit 5000GB
```

**Observe** — wait a few seconds, then:

```bash
sudo rabbitmq-diagnostics alarms
```

```bash
sudo rabbitmq-diagnostics check_local_alarms; echo "exit=$?"
```

Try to publish (gives up after 20 seconds):

```bash
timeout 20 python3 publish.py 3; echo "exit=$?"
```

**T2** — during those 20 seconds, look at the connection:

```bash
sudo rabbitmqctl -q list_connections user state
```

Read the log:

```bash
sudo grep -E 'alarm|Publishers' /var/log/rabbitmq/rabbit@$(hostname -s).log | tail -n 3
```

- **Expected:** `Free disk space alarm on node rabbit@<host>`; `check_local_alarms` prints `Error:` and `exit=69`; the publisher hangs and ends with `exit=124` (killed by `timeout`); the connection state is `blocked`; the log says:

```text
2026-11-15 08:25:41.708898+00:00 [warning] <0.297.0> disk resource limit alarm set on node 'rabbit@lab-laptop'.
2026-11-15 08:25:41.708898+00:00 [warning] <0.297.0> *** Publishers will be blocked until this alarm clears ***
```

**Recover** — restore the default limit (50 MB):

```bash
sudo rabbitmqctl set_disk_free_limit 50MB
```

**Verify** — wait a few seconds, then:

```bash
sudo rabbitmq-diagnostics alarms
```

```bash
python3 publish.py 3
```

- **Expected:** `reported no alarms`; `published 3 event(s)`. `sms` may show up to three messages more than you published now: the blocked publisher had already handed them over before `timeout` killed it, and the broker accepts them when the alarm clears (tested: `sms  4` and `sms  6`). On a real server, free disk space instead (old logs, a queue nobody reads).
- `set_disk_free_limit` changes only the running broker; a restart goes back to the default.

## 14. Stop and start the service: what clients see

**T2** — start a consumer:

```bash
python3 sms-consumer.py
```

**T1** — stop RabbitMQ:

```bash
sudo systemctl stop rabbitmq-server
```

- **Expected in T2:** the consumer dies; the last traceback line is:

```text
pika.exceptions.ConnectionClosedByBroker: (320, "CONNECTION_FORCED - broker forced connection closure with reason 'shutdown'")
```

Ping the broker:

```bash
sudo rabbitmq-diagnostics ping
```

Use the admin tool:

```bash
rabbitmqadmin list queues
```

Publish an event:

```bash
python3 publish.py 1 2>&1 | tail -n 1
```

- **Expected:** `Error: Failed to connect and authenticate to rabbit@<host> in 60000 ms` (ping may wait before it gives up); `*** Could not connect: [Errno 111] Connection refused`; `pika.exceptions.AMQPConnectionError`.
- **Why it matters:** while the broker is down, the **payment service** cannot hand over its event. A real producer must retry or keep the event safely (for example in its own database) — this is why the broker itself needs monitoring.

Start RabbitMQ:

```bash
sudo systemctl start rabbitmq-server
```

Check it:

```bash
sudo rabbitmq-diagnostics ping
```

Look at the queues:

```bash
sudo rabbitmqctl -q list_queues name messages consumers
```

- **Expected:** `Ping succeeded`; queues, exchanges, bindings and the policy are back; `sms` shows `consumers 0`. Our simple consumer does not reconnect by itself — someone (or systemd, in production) must restart it.

Read the stop/start in the journal:

```bash
sudo journalctl -u rabbitmq-server --no-pager | tail -n 4
```

## 15. Persistence: what survives a restart

- Two separate switches: a **durable queue** survives a restart; a **persistent message** (`delivery_mode=2`) is written to disk. A message survives only if **both** are true.

Create a non-durable queue bound like `sms`:

```bash
rabbitmqadmin declare queue name=sms.temp durable=false
```

```bash
rabbitmqadmin declare binding source=payments destination=sms.temp routing_key=payment.completed
```

Publish one event with rabbitmqadmin (non-persistent by default):

```bash
rabbitmqadmin publish exchange=payments routing_key=payment.completed payload='{"event":"PaymentCompleted","id":"P4004","amount":500,"phone":"+91-98450-00000"}'
```

Publish three persistent events with the script:

```bash
python3 publish.py 3
```

Count, including persistent messages:

```bash
sudo rabbitmqctl -q list_queues name durable messages messages_persistent
```

- **Expected:** `sms  true  4  3` and `sms.temp  false  4  0`.

Restart RabbitMQ:

```bash
sudo systemctl restart rabbitmq-server
```

Count again:

```bash
sudo rabbitmqctl -q list_queues name durable messages messages_persistent
```

- **Expected:** `sms  true  3  3` — P4004 (non-persistent) is gone; `sms.temp` is gone completely (not durable).

Show what survived:

```bash
rabbitmqadmin -f pretty_json get queue=sms count=5 ackmode=ack_requeue_true | jq -r '.[].payload'
```

- **Expected:** P1, P2, P3.

Publish a persistent message with rabbitmqadmin:

```bash
rabbitmqadmin publish exchange=payments routing_key=payment.completed payload='{"event":"PaymentCompleted","id":"P5005","amount":500,"phone":"+91-98450-00000"}' properties='{"delivery_mode":2}'
```

```bash
sudo rabbitmqctl -q list_queues name durable messages messages_persistent
```

- **Expected:** `sms  true  4  4`.

| Queue | Message | After restart |
| --- | --- | --- |
| durable | persistent | kept |
| durable | non-persistent (rabbitmqadmin default) | lost |
| not durable | any | queue and messages lost |

## 16. Handoff

- The Kafka and Security labs do not use RabbitMQ; it just stays up, clean, with no scripts running.
- Press **Ctrl+C** in T2 and T3 if anything still runs.

Confirm no lab script is still running:

```bash
pgrep -af 'python3 sms-' || echo "no consumers running"
```

Empty the work queues:

```bash
sudo rabbitmqctl purge_queue sms
```

```bash
sudo rabbitmqctl purge_queue fraud
```

Check the service:

```bash
systemctl is-active rabbitmq-server; systemctl is-enabled rabbitmq-server
```

Check the broker:

```bash
sudo rabbitmq-diagnostics ping
```

Save the final state as evidence:

```bash
sudo rabbitmqctl -q list_queues name durable policy messages consumers | tee ~/lab/evidence/day2/lab1-handoff.txt
```

Check the policy:

```bash
sudo rabbitmqctl -q list_policies
```

- **Expected:** `no consumers running`; `active`, `enabled`; `Ping succeeded`; queues `sms` (policy `sms-dlx`), `fraud`, `sms.dlq` all durable with `0` messages and `0` consumers; policy `sms-dlx` listed.

| Left running for the next labs | Value |
| --- | --- |
| Service | `rabbitmq-server` (active, enabled) |
| Ports | 5672, 15672, 25672, 4369 |
| Exchanges | `payments` (topic), `payments.dlx` (fanout) |
| Queues | `sms`, `fraud`, `sms.dlq` (durable, empty) |
| Policy | `sms-dlx` on `^sms$` |

## Check yourself

1. The SMS gateway is down for 10 minutes. What happens to payments with a broker in between, and without one?
2. `publish.py` printed "published" but `list_queues` shows no new message. Name two possible causes and the command that tells them apart.
3. `sms` shows `messages_ready 0`, `messages_unacknowledged 10`, `consumers 1`, unchanged for five minutes. What is wrong, and what happens to the 10 messages when you stop that consumer?
4. Why does a message with key `payment.failed` reach `fraud` but not `sms`? What would `payment.card.failed` do?
5. Two consumers share `sms`. Is the SMS order still guaranteed? When is a small prefetch better than a large one?
6. A consumer hits a message it can never process. Compare `requeue=True` and `requeue=False` with the `sms-dlx` policy in place.
7. `sms.dlq` jumped from 0 to 5,000 after a release. List your steps from detection to recovery, and say when it is safe to move the messages back.
8. After a restart, `sms` exists but some messages are missing. Which messages survive a restart, and why did rabbitmqadmin's test messages disappear?

- Model answers: [project-files/rabbitmq/ANSWERS.md](project-files/rabbitmq/ANSWERS.md).
