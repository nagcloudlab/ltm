# Module 10 — Kafka and RabbitMQ in operation: build notes

Generator: `gen2/m10.py` (runs `m10a.py` Kafka partitions/offsets, `m10b.py` lag/imbalance/rebalances/offset resets/retention,
`m10c.py` RabbitMQ exchanges, `m10d.py` queue monitoring, `m10e.py` alarms/stuck/DLQ/recovery/summary/lab/QC).
Shared helpers in `gen2/m10common.py`; all captured terminal output lives in `gen2/m10cap.py` (plus inline in the part files).
Raw captures: `$S/m10cap/*.txt`; lab scripts used for the demos: `lab/` (publish.py, sms-noack.py, sms-poison.py,
sms-rejectall.py, sms-consumer.py, k*.sh, r*.sh).

## Versions tested (container `d2-m10`, image mw-ubuntu-test:24.04, arm64)
- Kafka **4.4.0** (`kafka_2.13-4.4.0.tgz`, latest on downloads.apache.org on 2026-11-15), KRaft combined mode, OpenJDK 21 (Ubuntu package).
  - `/opt/kafka`, systemd unit `kafka` (User=kafka, `KAFKA_HEAP_OPTS=-Xmx512m -Xms512m`), `log.dirs=/var/lib/kafka`
    (formatted with `kafka-storage.sh format --standalone -t <uuid> -c config/server.properties`), logs `/opt/kafka/logs/server.log`.
  - Ports 9092 (PLAINTEXT) and 9093 (CONTROLLER) from the stock `config/server.properties`.
- RabbitMQ **3.12.1** (`rabbitmq-server 3.12.1-1ubuntu1.7`, Erlang 25.3.2.8), management plugin, `rabbitmqadmin` downloaded from
  `http://localhost:15672/cli/rabbitmqadmin`, `python3-pika 1.2.0` for the lab consumers. Shovel plugins enabled during the recovery demo.

## Substitutions on slides
- Container hostname replaced by the Day 1 VM name **lab-vm-01** (`rabbit@lab-vm-01`).
- Long Kafka lines are split over two slide lines or shown as tables (columns are real values; TOPIC column dropped from the
  group tables because it is always `payments`). Tabs rendered as spaces.

## Facts other modules must stay consistent with
- Kafka 4.4 console tools: `--property` is DEPRECATED → producer uses `--reader-property parse.key=true --reader-property key.separator=:`,
  consumer uses `--formatter-property print.key=true` etc.; `--consumer-property/--producer-property` are DEPRECATED → `--command-property`.
- Console consumer prints at start: "The consumer rebalance protocol (KIP-848) is production-ready! Set group.protocol=consumer to try it out."
  (client default is still `classic`).
- `kafka-topics.sh --describe` in 4.4 prints `Elr:` and `LastKnownElr:` columns.
- Key → partition on our 3-partition `payments`: acc-1001 → 1, acc-2002 → 0, acc-3003 → 2, acc-4004 → 1.
- RabbitMQ objects created in Module 10 (Module 9 may have created some already — names identical):
  exchange `payments` **type topic** (durable), `payments.dlx` **type fanout**, queue `sms` with `x-dead-letter-exchange=payments.dlx`,
  `sms.dlq` bound to `payments.dlx` with empty key, queue `fraud` bound with `payment.#`; `sms` bound with routing key `payment.completed`.
  **If Module 9 declares `payments` as a different type, one of the two must change** (redeclaring with another type fails).
- RabbitMQ 3.12.1 defaults verified: `vm_memory_high_watermark 0.4`, `disk_free_limit 50000000` (50 MB), `consumer_timeout 1800000`.
- Lab scripts expected in `~/lab` on the student VM (see `lab/`).

## Verified for real (all output on slides captured in the container; raw files in `$S/m10cap/`)
Kafka 4.4.0:
- `kafka-topics.sh --describe` (Leader/Replicas/Isr/Elr/LastKnownElr), `--under-replicated-partitions` (prints nothing).
- Keyed produce (`--reader-property parse.key/key.separator`) and consume with `--formatter-property print.partition/offset/key`.
- `kafka-consumer-groups.sh --describe` running / stopped ("has no active members"), `--state`, `--members`, `--members --verbose`,
  backlog 3,000 → lag 867/1356/777; hot key 2,000 × acc-1001 → partition 1 lag 3,414; 4 consumers → sms-4 has #PARTITIONS 0.
- server.log rebalance lines (Preparing to rebalance … reason, Stabilized … generation N with M members, LeaveGroup, "is now empty").
- One real rebalance-storm cycle: consumer WARN "consumer poll timeout has expired …", broker "left group … client reason: consumer poll timeout has expired", second run (on the slide) with max.poll.interval.ms 10 s: 4 leave/re-join cycles, generation 14→22 in under 2 minutes (k9.txt).
- Consumer defaults printed by the 4.4 client: session.timeout.ms 45000, heartbeat.interval.ms 3000, max.poll.interval.ms 300000,
  max.poll.records 500, auto.offset.reset latest, enable.auto.commit true / 5000 ms, group.protocol classic,
  partition.assignment.strategy [RangeAssignor, CooperativeStickyAssignor].
- Broker: group.initial.rebalance.delay.ms 3000, group.consumer.session.timeout.ms 45000, group.consumer.heartbeat.interval.ms 5000,
  offsets.retention.minutes 10080, log.retention.hours 168 → topic retention.ms 604800000, log.retention.check.interval.ms 300000.
- KIP-848: `--command-property group.protocol=consumer` works; `--state` shows ASSIGNMENT-STRATEGY `uniform`; server.log
  "joins the consumer group using the consumer protocol", "Bumped group epoch", "Computed a new target assignment … 'uniform' assignor".
- Offset reset: active-group error ("Assignments can only be reset if the group … is inactive, but the current state is Stable."),
  `--shift-by -100 --dry-run` (with WARN "New offset (-21) is lower than earliest offset …"), no-mode WARN about 5.0,
  missing scope error, GroupIdNotFoundException on a typo, `--to-datetime` dry-run/execute (8,000 replayed).
  **Time zone:** a datetime without offset is read as UTC even with TZ / -Duser.timezone=Asia/Kolkata; `+05:30` suffix works.
RabbitMQ 3.12.1:
- list_exchanges, list_bindings, rabbitmqadmin declare/list/publish, routing quiz (5 bindings × keys: routed / "NOT routed"),
  errors "404 NOT_FOUND - no exchange 'paymnts'", "inequivalent arg 'x-dead-letter-exchange'"; rabbitmqctl without sudo prints usage.
- list_queues/list_consumers/list_channels for: no consumer, never-acking consumer (190/10, prefetch 10), unacked returned on kill,
  poison message (5,684 redeliveries in 10 s, redeliver rate 382/s), DLQ flood (sms.dlq 500), x-death headers via HTTP API.
- rabbitmq-diagnostics ping/check_running/check_local_alarms/check_port_connectivity/status/alarms; environment values
  vm_memory_high_watermark 0.4, disk_free_limit 50000000, consumer_timeout 1800000.
- Disk alarm via `set_disk_free_limit 5000GB`: "Free disk space alarm on node", publisher hung (exit 124), connection `blocked`,
  log "disk resource limit alarm set … *** Publishers will be blocked until this alarm clears ***", cleared after 50MB;
  check_local_alarms exit 69.
- consumer_timeout lowered to 15 s at runtime: pika ChannelClosedByBroker 406 PRECONDITION_FAILED, broker warning line.
- Shovel (src-delete-after queue-length) moving 500 from sms.dlq to sms; purge_queue output.

## Not run for real / drawn
- Management UI Queues table (m10-ui-queues) is a drawn mock-up using real numbers from the never-ack demo; rates shown as 0.00/s
  match that state but the UI was not screenshotted.
- 3-broker leader/Isr picture (m10-leader) is illustrative; our lab has one broker.
- `kafka-topics.sh --alter --partitions 6` is shown but deliberately not executed (topic must stay at 3 partitions).
- Memory alarm (only the disk alarm was triggered); RabbitMQ 4.x quorum-queue delivery-limit default 20 is from release notes, not tested.
- Lag "alert thresholds" are example values, not product defaults (stated on slide).

## Other notes
- Renders: `gen2/m10render.py` is a copy of render2.py with its own Chrome profile (the shared profile silently failed while other
  agents rendered). PNGs in `mw-day2/render/m10-*.png`, contact sheets `m10all*.png`.
- Module 10 creates queue `fraud` (bound `payment.#`) in RabbitMQ; Module 11+ can reuse it.
- `~/lab` scripts needed on student VMs: publish.py, sms-noack.py, sms-poison.py, sms-rejectall.py, sms-consumer.py (python3-pika).
- Slide count 78 (target was ~60): 13 short Try-its (3–5 min) + lab + QC; trim candidates if time is short: m10-four, m10-leader,
  m10-ex-direct/m10-ex-topic merge, m10-ack-timeout, m10-kip848, m10-try-storm (trainer demo instead).
