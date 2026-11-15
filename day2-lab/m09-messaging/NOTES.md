# Module 9 · Messaging basics — build notes

55 slides, ids in `order-m9.txt` (first = `m9-div`). Generator: `gen2/m9.py` (helper `gen2/m9sheet.py` only makes review contact sheets). Raw test transcripts: `$S/m9t/*.out` (rmq.out, rmq2.out, kafka.out, kafka2.out, kafka3.out, web.out) and the scripts that produced them (`$S/m9t/*.sh`).

## Versions tested (Docker `mw-ubuntu-test:24.04`, hostname set to `lab-vm-01`)
- RabbitMQ **3.12.1** (`rabbitmq-server 3.12.1-1ubuntu1.7`, Ubuntu 24.04 apt), Erlang/OTP 25 (`erlang-base 25.3.2.8`).
- Kafka **4.4.0** (`kafka_2.13-4.4.0.tgz` from downloads.apache.org), KRaft combined mode, OpenJDK **21.0.13**.
- Nginx 1.24.0 (only for the 504 capture), Python 3.12.3 stand-in app (202 capture).

## Facts other modules must stay consistent with
- Kafka: `/opt/kafka`, user `kafka` (nologin), data dir **`/var/lib/kafka`** (sed on `log.dirs`, default was `/tmp/kraft-combined-logs`), logs `/opt/kafka/logs/server.log`, systemd unit `/etc/systemd/system/kafka.service` with `User=kafka`, `JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64` on slides, `KAFKA_HEAP_OPTS=-Xmx512m -Xms512m`, `Restart=on-failure`. Shipped server.properties: `process.roles=broker,controller`, `node.id=1`, `listeners=PLAINTEXT://:9092,CONTROLLER://:9093`, `num.partitions=1`, `log.retention.hours=168`. Format: `kafka-storage.sh random-uuid` then `format --standalone -t $ID -c …` run as kafka → "Formatting dynamic metadata voter directory /var/lib/kafka with metadata.version 4.4-IV2."
- Start check line: `INFO [KafkaRaftServer nodeId=1] Kafka Server started`. systemd showed active ~2 min before that line on the loaded test host.
- Topic `payments`, 3 partitions, RF 1. Groups created in Module 9: `notification-service` (2 members: payments:0,1 and payments:2), `fraud-check` (1 member). Key demo: ACC-1001 → partition 1, ACC-2002 → partition 2 (hash; students may differ).
- **Kafka 4.4 console tools**: `--property` is deprecated → use `--formatter-property` (consumer) and `--reader-property` (producer). Consumer prints a KIP-848 info line ("The consumer rebalance protocol (KIP-848) is production-ready! …") — Module 10 may want to explain it.
- `kafka-consumer-groups --describe --members --verbose` in 4.4 has columns `GROUP CONSUMER-ID HOST CLIENT-ID #PARTITIONS CURRENT-EPOCH CURRENT-ASSIGNMENT TARGET-EPOCH TARGET-ASSIGNMENT`. Module 9 did NOT show the offsets/lag view (left for Module 10).
- Kafka tools pointed at 9093 / a wrong port / stopped Kafka print nothing (we cut at 30 s); the default ends with `Timed out waiting for a node assignment. Call: listTopics` (seen for real under load).
- RabbitMQ: process `beam.smp` (user rabbitmq), ports 5672 (AMQP), 25672 (CLI/cluster), 4369 (epmd), 15672 after `rabbitmq-plugins enable rabbitmq_management`. Node `rabbit@lab-vm-01`, log `/var/log/rabbitmq/rabbit@lab-vm-01.log`. guest from non-localhost → `{"error":"not_authorised","reason":"User can only log in via localhost"}`.
- `rabbitmqadmin` downloaded from `http://localhost:15672/cli/rabbitmqadmin` to `/usr/local/bin/`.
- Objects left on the VM after Module 9: exchange `payments` (**type topic**, matching Modules 10/13) → binding key **`payment.completed`** → durable classic queue `sms`; producers publish with routing key `payment.completed`; exchange `payments.dlx` (fanout) → durable queue `sms.dlq`; **policy `sms-dlx`** pattern `^sms$` `{"dead-letter-exchange":"payments.dlx"}` (a policy, not an x-dead-letter-exchange queue argument; slide mentions the argument as the alternative).
- DLQ evidence: `x-death` with `reason: rejected` (get ackmode=reject_requeue_false) and `reason: expired` (publish with `properties='{"expiration":"5000"}'`). Module 9 introduced reasons rejected/expired and named maxlen/delivery_limit only in notes.
- Exchange types are not taught in Module 9 (one line: “Module 10 explains exchange types”).
- `rabbitmqadmin publish` with wrong routing key (`payment.complete`) → `Message published but NOT routed`; with RabbitMQ stopped → `*** Could not connect: [Errno 111] Connection refused`.
- Messages published by rabbitmqadmin are non-persistent by default: after a restart the queues exist but those messages are gone (rabbitmqadmin list right after restart showed empty message counts). Relevant if Module 10 restarts RabbitMQ.
- New status code introduced here: **202 Accepted** (with Location header). URL used: `POST /payment/transfer` (not in Day 1 payment.war).
- Analogies used: post box/post office (producer/broker/consumer), bank token counter (queue), office notice board (topic), courier A/B (at-most/at-least-once), returned-letter office (DLQ), branch register with bookmarks (Kafka log; "offset" named only as Module 10's word).

## Real vs not verified
- Real output: all RabbitMQ and Kafka terminal content; 504 via Nginx 1.24 with proxy_read_timeout 10s (real 0m10.340s) against a Python stand-in that sleeps 12 s; 202 from a Python stand-in (so it shows `HTTP/1.0` and `Server: BaseHTTP/0.6 Python/3.12.3`; notes say Tomcat would say HTTP/1.1).
- Cosmetic edits: amd64 JAVA_HOME (host was arm64); ss/list_queues spacing tightened; long lines trimmed with …; groups-describe columns trimmed with …; group-demo commands shown with `--formatter-property`, while that particular capture used the deprecated `--property` (the new flags were verified separately in kafka3.out with identical output format).
- Kafka `--list` on a fresh install (empty) not captured (the attempt timed out on the overloaded host); later list showed `__consumer_offsets`, `payments`.
- Management UI slide is a drawn mock (column names/versions real).
- NOT run: IBM MQ (developer image has no arm64 build; amd64 pull failed through the proxy), Azure Service Bus, AWS SQS/SNS — those slides contain no command output, only names/defaults: SQS visibility timeout 30 s, FIFO `.fifo` suffix + 5-min dedup, Service Bus lock duration 1 min, MaxDeliveryCount 10, `$DeadLetterQueue`, IBM MQ listener 1414, `SYSTEM.DEAD.LETTER.QUEUE`, `DEV.APP.SVRCONN`/`DEV.QUEUE.1`/`QM1` (IBM developer defaults).
