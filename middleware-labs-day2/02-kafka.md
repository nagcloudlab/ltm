# Lab 2 — Stream payment events with Kafka

- **Needs:** [Lab 1](01-rabbitmq.md) finished; the Day 1 Java 21 runtime (`/usr/lib/jvm/java-21-lab`); internet access to download Kafka (about 130 MB)
- **You build:** a single-node Kafka 4.4 broker under systemd, topic `payments` with 3 partitions, consumer groups `notification-service` and `fraud-check`, and the skills to read lag, rebalances and replays

```text
payment events -> Kafka 127.0.0.1:9092 -> topic payments (partitions 0, 1, 2)
                                             |-> group notification-service (sends SMS; members share the partitions)
                                             |-> group fraud-check          (gets its own copy of every event)
Kafka controller (cluster metadata) 127.0.0.1:9093
```

- The same **PaymentCompleted** story as Lab 1. Console tools and one small script stand in for the services; no coding.
- Keep **three terminals** open: **T1** for commands, **T2** and **T3** for consumers. Stop a consumer with **Ctrl+C**. Commands without a terminal label run in T1.

## 1. RabbitMQ and Kafka — what changes

- RabbitMQ is a **queue you empty**: a message is deleted once a consumer acknowledges it.
- Kafka is a **log you replay**: every event is appended to a file and stays there for the retention time (7 days here), whoever reads it.

| Question | RabbitMQ (Lab 1) | Kafka (this lab) |
| --- | --- | --- |
| Where do messages wait? | Queue `sms`, queue `fraud` | Topic `payments`, split into partitions |
| What happens after a read? | Acked message is deleted | Event stays; only the reader's bookmark moves |
| Two services need every event | One queue each, bound to the exchange | One **consumer group** each, same topic |
| Read old events again? | No, once acked it is gone | Yes: move the group's offset back and replay |
| Order kept | Per queue | Per partition (same key → same partition) |
| How far behind is a reader? | Messages ready / unacked | **Lag** = last offset in partition − group's offset |

| Kafka word | Plain meaning |
| --- | --- |
| Broker | The Kafka server process that stores events |
| Topic / partition | A named stream / one numbered append-only file of that stream |
| Offset | Position of an event inside a partition (0, 1, 2 …) — a bookmark |
| Consumer group | One service; its members share the partitions and one set of bookmarks |
| Lag | Events written but not yet read by the group |

Check that RabbitMQ from Lab 1 is still running:

```bash
systemctl is-active rabbitmq-server
```

Check the Java runtime Kafka will use:

```bash
/usr/lib/jvm/java-21-lab/bin/java -version
```

Check that the Kafka ports are free:

```bash
sudo ss -lntp | grep -E ':909[23] '
```

Check free memory:

```bash
free -m
```

- **Expected:** `active`; Java `21`; the `ss` line prints nothing; a few hundred MB or more in the `available` column.
- **Why memory:** the laptop already runs Tomcat, Kong and RabbitMQ. Kafka gets a fixed 512 MB heap, and the command-line tools get 128 MB each (step 7).

## 2. Download Kafka and verify the checksum

- Kafka is not an Ubuntu package. You download Apache's binary tarball and check that it arrived unchanged.

Create a downloads folder and go there:

```bash
mkdir -p ~/lab/downloads && cd ~/lab/downloads
```

Download Kafka 4.4.0 (Scala 2.13 build):

```bash
curl -fLO https://archive.apache.org/dist/kafka/4.4.0/kafka_2.13-4.4.0.tgz
```

Copy the supplied checksum file next to it:

```bash
cp ~/ltm/middleware-labs-day2/project-files/kafka/kafka_2.13-4.4.0.tgz.sha512 .
```

Verify the checksum:

```bash
sha512sum -c kafka_2.13-4.4.0.tgz.sha512
```

- **Expected:** `kafka_2.13-4.4.0.tgz: OK`. Do not continue if it says `FAILED`.

Look at Apache's own checksum file:

```bash
curl -fsS https://archive.apache.org/dist/kafka/4.4.0/kafka_2.13-4.4.0.tgz.sha512
```

- Sample output:

```text
kafka_2.13-4.4.0.tgz: F5CEBA8A 265AB6BB 2D68362B 1F6859A9 5E15D60E F92BA83B
                      43FDF065 B557DC18 E98D6383 C15B9977 320E25B3 A2C8B6F1
                      1DECB17B 0FA6C0F1 63423793 A0EB95CB
```

- **Why a supplied file:** Apache writes this file in the `gpg --print-md` layout (upper case, groups of 8, split over lines). `sha512sum -c` cannot read it and says `no properly formatted checksum lines found`. The supplied file holds the **same hash** in the one-line `hash  filename` layout that `sha512sum -c` expects — compare the first characters `f5ceba8a 265ab6bb …`.

## 3. Create the `kafka` user and install the files

- Same pattern as Tomcat in Day 1: program files owned by root, data and logs owned by a service account that cannot log in.

Create the service account:

```bash
sudo useradd --system --user-group --home-dir /var/lib/kafka --shell /usr/sbin/nologin kafka
```

Extract the tarball into `/opt`:

```bash
sudo tar -xzf kafka_2.13-4.4.0.tgz -C /opt
```

Rename the folder to a stable path:

```bash
sudo mv /opt/kafka_2.13-4.4.0 /opt/kafka
```

Make root the owner of the program files:

```bash
sudo chown -R root:root /opt/kafka
```

Create the log folder (owned by `kafka`, readable by you):

```bash
sudo install -d -o kafka -g kafka -m 755 /opt/kafka/logs
```

Create the data folder (owned by `kafka`, private):

```bash
sudo install -d -o kafka -g kafka -m 750 /var/lib/kafka
```

List the main tools you will use:

```bash
ls /opt/kafka/bin | grep -E '^kafka-(server|storage|topics|console-(producer|consumer)|consumer-groups|configs|metadata-quorum)'
```

- **Expected:** `kafka-configs.sh`, `kafka-console-consumer.sh`, `kafka-console-producer.sh`, `kafka-consumer-groups.sh`, `kafka-metadata-quorum.sh`, `kafka-server-start.sh`, `kafka-server-stop.sh`, `kafka-storage.sh`, `kafka-topics.sh`.

| Path | Purpose |
| --- | --- |
| `/opt/kafka/bin/` | Start script and command-line tools |
| `/opt/kafka/config/server.properties` | Broker configuration |
| `/var/lib/kafka/` | Data: one folder per partition (`payments-0` …) |
| `/opt/kafka/logs/server.log` | Broker log — start, stop, group rebalances |

## 4. Configure a single KRaft node

- **KRaft** = Kafka keeps its own cluster metadata (no ZooKeeper). On one laptop, the same process is the **broker** (stores events, port 9092) and the **controller** (keeps metadata, port 9093).

Keep a copy of the stock file:

```bash
cp /opt/kafka/config/server.properties ~/lab/backups/kafka-server.properties.orig
```

Install the supplied configuration:

```bash
sudo install -o root -g kafka -m 644 ~/ltm/middleware-labs-day2/project-files/kafka/server.properties /opt/kafka/config/server.properties
```

Read the active settings:

```bash
grep -vE '^#|^$' /opt/kafka/config/server.properties
```

Compare with the stock file:

```bash
diff <(grep -vE '^#|^$' ~/lab/backups/kafka-server.properties.orig) <(grep -vE '^#|^$' /opt/kafka/config/server.properties)
```

- **Expected:** the stock file listened on all interfaces (`PLAINTEXT://:9092`) and stored data in `/tmp/kraft-combined-logs`. Ours listens on `127.0.0.1` only and stores data in `/var/lib/kafka`; a few tuning lines are left at their defaults.

| Setting | Value | Meaning |
| --- | --- | --- |
| `process.roles` | `broker,controller` | One process does both jobs |
| `node.id` | `1` | This node's number (shows as `Leader: 1` later) |
| `listeners` | `PLAINTEXT://127.0.0.1:9092,CONTROLLER://127.0.0.1:9093` | Clients on 9092, controller on 9093, loopback only |
| `log.dirs` | `/var/lib/kafka` | Where events are stored (not `/tmp`, which is wiped at boot) |
| `log.retention.hours` | `168` | Keep events 7 days |

## 5. Format the storage

- KRaft needs a **cluster ID** written into the data folder once, before the first start.

Generate a cluster ID:

```bash
KAFKA_CLUSTER_ID=$(/opt/kafka/bin/kafka-storage.sh random-uuid)
```

Show it:

```bash
echo $KAFKA_CLUSTER_ID
```

Format the data folder as the `kafka` user:

```bash
sudo -u kafka /opt/kafka/bin/kafka-storage.sh format --standalone -t "$KAFKA_CLUSTER_ID" -c /opt/kafka/config/server.properties
```

- **Expected:** last line `Formatting dynamic metadata voter directory /var/lib/kafka with metadata.version 4.4-IV2.` (a long `Bootstrap metadata: …` line before it is normal).
- `--standalone` = this node is the only controller voter.

List what the format created:

```bash
sudo ls -l /var/lib/kafka
```

Read the identity file:

```bash
sudo cat /var/lib/kafka/meta.properties
```

- **Expected:** a `__cluster_metadata-0` folder and `meta.properties` with your `cluster.id` and `node.id=1`.
- **If it fails:** `Log directory /var/lib/kafka is already formatted` means you ran it twice — that is fine, carry on. Never delete `/var/lib/kafka` on a broker that holds real data.

## 6. Run Kafka under systemd

Read the supplied unit:

```bash
cat ~/ltm/middleware-labs-day2/project-files/kafka/kafka.service
```

- `User=kafka`, `JAVA_HOME=/usr/lib/jvm/java-21-lab` (the Day 1 link), heap `-Xmx512m -Xms512m`, `After=network.target`, `Restart=on-failure`.

Install the unit:

```bash
sudo install -o root -g root -m 644 ~/ltm/middleware-labs-day2/project-files/kafka/kafka.service /etc/systemd/system/kafka.service
```

Reload systemd:

```bash
sudo systemctl daemon-reload
```

Start Kafka now and at every boot:

```bash
sudo systemctl enable --now kafka
```

Check the service:

```bash
systemctl is-active kafka
```

Wait for the start line in the broker log:

```bash
until grep -q 'Kafka Server started' /opt/kafka/logs/server.log 2>/dev/null; do sleep 2; done; grep 'Kafka Server started' /opt/kafka/logs/server.log
```

- **Expected:** `active`, then the start line (a few seconds on a quiet laptop; up to 2 minutes on a busy one).
- Sample line:

```text
[2026-11-15 08:09:13,502] INFO [KafkaRaftServer nodeId=1] Kafka Server started (kafka.server.KafkaRaftServer)
```

- **Why wait for the log line:** systemd says `active` as soon as Java starts; clients can connect only after `Kafka Server started`.
- **If it fails:** `sudo journalctl -u kafka -n 50 --no-pager` and `tail -n 50 /opt/kafka/logs/server.log`. Common causes: storage not formatted (step 5), wrong `JAVA_HOME`, port already in use.

## 7. Prove Kafka is up

Show the Java process and its memory:

```bash
ps -o user,pid,rss,args -u kafka | cut -c1-110
```

Show the two listening ports:

```bash
sudo ss -lntp | grep -E ':909[23] '
```

- **Expected:** one `java` process run by `kafka` with `-Xmx512m -Xms512m`; ports `127.0.0.1:9092` and `127.0.0.1:9093`, both owned by that `java` PID.
- Sample output:

```text
USER         PID   RSS COMMAND
kafka       2756 348308 /usr/lib/jvm/java-21-lab/bin/java -Xmx512m -Xms512m -server -XX:+UseG1GC -XX:MaxGCPauseMillis=20
LISTEN 0      50     [::ffff:127.0.0.1]:9092             *:*    users:(("java",pid=2756,fd=169))
LISTEN 0      50     [::ffff:127.0.0.1]:9093             *:*    users:(("java",pid=2756,fd=137))
```

List the log files:

```bash
ls -l /opt/kafka/logs
```

- `server.log` is the main log; `controller.log` holds metadata decisions; `kafkaServer-gc.log` holds garbage collection.

Put the Kafka tools on your PATH (every new terminal):

```bash
echo 'export PATH=$PATH:/opt/kafka/bin' >> ~/.bashrc
```

Give the tools a small heap (they default to 512 MB each):

```bash
echo 'export KAFKA_HEAP_OPTS="-Xmx128m"' >> ~/.bashrc
```

Load the changes in this terminal:

```bash
source ~/.bashrc
```

- This setting is read only by tools you start from your shell. The broker keeps its 512 MB from the systemd unit.

Ask the controller for its status:

```bash
kafka-metadata-quorum.sh --bootstrap-server localhost:9092 describe --status
```

- **Expected:** `LeaderId: 1` and `CurrentVoters` with id 1 on `CONTROLLER://localhost:9093` — the controller is elected and the broker answers on 9092.
- Sample output:

```text
ClusterId:              e8FfsHdISAStneotTM3Xyg
LeaderId:               1
LeaderEpoch:            1
HighWatermark:          21
MaxFollowerLag:         0
MaxFollowerLagTimeMs:   0
CurrentVoters:          [{"id": 1, "directoryId": "bfVrly_GQcu8a2yHxas7Wg", "endpoints": ["CONTROLLER://localhost:9093"]}]
CurrentObservers:       []
```

Save the evidence:

```bash
{ systemctl is-active kafka; sudo ss -lntp | grep -E ':909[23] '; grep 'Kafka Server started' /opt/kafka/logs/server.log | tail -n 1; } | tee ~/lab/evidence/day2/kafka-up.txt
```

## 8. Create the `payments` topic

- A topic is created once. **3 partitions** let up to 3 consumers of one group work in parallel. **Replication factor 1**: one broker, so one copy.

List topics (empty on a new broker):

```bash
kafka-topics.sh --bootstrap-server localhost:9092 --list
```

Create the topic:

```bash
kafka-topics.sh --bootstrap-server localhost:9092 --create --topic payments --partitions 3 --replication-factor 1
```

List again:

```bash
kafka-topics.sh --bootstrap-server localhost:9092 --list
```

Describe it:

```bash
kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic payments
```

- **Expected:** `Created topic payments.`, then `payments` in the list, then one line per partition.
- Sample output:

```text
Topic: payments	TopicId: XS1vHGTlTRmfld8nFYi8LA	PartitionCount: 3	ReplicationFactor: 1	Configs: min.insync.replicas=1,segment.bytes=1073741824
	Topic: payments	Partition: 0	Leader: 1	Replicas: 1	Isr: 1	Elr: 	LastKnownElr: 
	Topic: payments	Partition: 1	Leader: 1	Replicas: 1	Isr: 1	Elr: 	LastKnownElr: 
	Topic: payments	Partition: 2	Leader: 1	Replicas: 1	Isr: 1	Elr: 	LastKnownElr: 
```

| Column | Meaning |
| --- | --- |
| `Leader: 1` | Broker (node.id) that serves reads and writes for this partition |
| `Replicas: 1` | Brokers that hold a copy |
| `Isr: 1` | In-sync replicas: copies that are up to date (empty = trouble) |
| `Elr` / `LastKnownElr` | Eligible leader replicas — only matter with several brokers |

See the partition folders on disk:

```bash
sudo ls /var/lib/kafka
```

- **Expected:** `payments-0`, `payments-1`, `payments-2` next to `__cluster_metadata-0`.
- **If it fails:** creating it again prints `Topic 'payments' already exists.` — harmless.

## 9. Send and read your first events

- The console producer sends each input line as one event; the console consumer prints events.

Send three events:

```bash
printf 'PaymentCompleted PAY-1001\nPaymentCompleted PAY-1002\nPaymentCompleted PAY-1003\n' | kafka-console-producer.sh --bootstrap-server localhost:9092 --topic payments
```

Read everything from the start, then stop after 3:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --from-beginning --max-messages 3
```

Read the same events again, with partition and offset:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --from-beginning --max-messages 3 --formatter-property print.partition=true --formatter-property print.offset=true
```

- **Expected:** the three events, then `Processed a total of 3 messages` — twice. Reading did not delete anything.
- Sample output:

```text
Partition:1	Offset:0	PaymentCompleted PAY-1001
Partition:1	Offset:1	PaymentCompleted PAY-1002
Partition:1	Offset:2	PaymentCompleted PAY-1003
Processed a total of 3 messages
```

- The first line `The consumer rebalance protocol (KIP-848) is production-ready! …` is an information notice from Kafka 4.4 — ignore it.
- Events without a key are sent in batches to one partition (your partition number may differ).
- **Compare with Lab 1:** a second `basic_get` on an emptied RabbitMQ queue returns nothing; Kafka simply reads the log again.

## 10. Keys decide the partition — order per key

- Give each event a **key** (here the account number). Kafka hashes the key: the same key always lands in the same partition, so events for one account stay in order.
- `parse.key=true` and `key.separator=:` mean "text before the first `:` is the key".

Send six keyed events:

```bash
printf 'acc-1001:PaymentCreated PAY-5001\nacc-2002:PaymentCreated PAY-5002\nacc-1001:PaymentCompleted PAY-5001\nacc-2002:PaymentCompleted PAY-5002\nacc-1001:RefundIssued PAY-5001\nacc-3003:PaymentCompleted PAY-5003\n' | kafka-console-producer.sh --bootstrap-server localhost:9092 --topic payments --reader-property parse.key=true --reader-property key.separator=:
```

Read the whole topic with partition, offset and key (stops 10 s after the last event):

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --from-beginning --timeout-ms 10000 --formatter-property print.partition=true --formatter-property print.offset=true --formatter-property print.key=true
```

- **Expected:** all events of one account in **one** partition, in the order sent (Created → Completed → Refund).
- Sample output:

```text
Partition:0	Offset:0	acc-2002	PaymentCreated PAY-5002
Partition:0	Offset:1	acc-2002	PaymentCompleted PAY-5002
Partition:2	Offset:0	acc-3003	PaymentCompleted PAY-5003
Partition:1	Offset:0	null	PaymentCompleted PAY-1001
Partition:1	Offset:1	null	PaymentCompleted PAY-1002
Partition:1	Offset:2	null	PaymentCompleted PAY-1003
Partition:1	Offset:3	acc-1001	PaymentCreated PAY-5001
Partition:1	Offset:4	acc-1001	PaymentCompleted PAY-5001
Partition:1	Offset:5	acc-1001	RefundIssued PAY-5001
[2026-11-15 08:10:18,481] ERROR Error processing message, terminating consumer process:  (org.apache.kafka.tools.consumer.ConsoleConsumer)
org.apache.kafka.common.errors.TimeoutException
Processed a total of 9 messages
```

- With 3 partitions, `acc-1001` → 1, `acc-2002` → 0, `acc-3003` → 2 (the hash is fixed, so you should see the same).
- The `ERROR … TimeoutException` at the end only means "no new event for 10 s" (`--timeout-ms`) — not a fault.
- **Order is per partition, not per topic:** partition 0 events print before partition 1 events, although some were sent later.

Read only partition 1, from its first offset:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --partition 1 --offset earliest --timeout-ms 8000 --formatter-property print.offset=true --formatter-property print.key=true
```

- **Expected:** partition 1 only: the three `acc-1001` events, plus the three events without a key if they landed in partition 1 (offsets 0–5 in the sample run; 0–2 when they went to another partition).

Copy the event generator into your lab folder:

```bash
mkdir -p ~/lab/kafka && cp ~/ltm/middleware-labs-day2/project-files/kafka/gen-payments.sh ~/lab/kafka/
```

Print three sample events:

```bash
~/lab/kafka/gen-payments.sh 3
```

- Sample output:

```text
acc-1022:{"event":"PaymentCompleted","id":"PAY-133711-1","amount":500}
acc-1033:{"event":"PaymentCompleted","id":"PAY-133711-2","amount":500}
acc-1048:{"event":"PaymentCompleted","id":"PAY-133711-3","amount":500}
```

- `gen-payments.sh COUNT [KEY]` prints `key:json` lines with random accounts `acc-1000`…`acc-1049`, or one fixed key. You pipe it into the producer from now on.

## 11. Consumer groups — share the work, or get your own copy

- Members of the **same group** split the partitions: each event goes to one member.
- A **different group** reads the topic independently and gets every event.

**T2** — start the first SMS sender:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group notification-service --formatter-property print.partition=true --formatter-property print.key=true
```

**T1** — see the group and its member:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service --members
```

- **Expected:** one member with `#PARTITIONS 3`. A new group starts at the **end** of the topic, so T2 prints nothing yet.

**T3** — start a second SMS sender in the same group:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group notification-service --formatter-property print.partition=true --formatter-property print.key=true
```

**T1** — wait a few seconds, then see who owns which partitions:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service --members --verbose
```

- **Expected:** two members; one has 2 partitions, the other 1.
- Sample output:

```text
GROUP                CONSUMER-ID                                           HOST            CLIENT-ID        #PARTITIONS     CURRENT-EPOCH   CURRENT-ASSIGNMENT   TARGET-EPOCH    TARGET-ASSIGNMENT
notification-service console-consumer-57ed86d6-7762-4823-bd6c-35fd8da816f2 /127.0.0.1      console-consumer 1               -               payments:2           -               -
notification-service console-consumer-00680b4a-b8a8-4225-b61c-6bb99117f21b /127.0.0.1      console-consumer 2               -               payments:0,1         -               -
```

**T1** — publish six payments:

```bash
~/lab/kafka/gen-payments.sh 6 | kafka-console-producer.sh --bootstrap-server localhost:9092 --topic payments --reader-property parse.key=true --reader-property key.separator=:
```

- **Expected:** T2 and T3 together print the six events; each event appears in **only one** of them, and each terminal shows only its own partitions.
- Sample output (T3, owner of partition 2):

```text
Partition:2	acc-1028	{"event":"PaymentCompleted","id":"PAY-081631-3","amount":500}
```

**T1** — the fraud-check service reads the whole topic in its own group:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group fraud-check --from-beginning --timeout-ms 10000 --formatter-property print.partition=true --formatter-property print.key=true
```

- **Expected:** every event in the topic, including the six that the SMS senders already read (15 in the sample run).
- `--from-beginning` matters only the first time a group starts; after that the group continues from its saved offset.

List all groups:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list
```

- **Expected:** `notification-service`, `fraud-check`, and some `console-consumer-NNNNN` groups — the consumers you ran without `--group` got a throw-away group each.

## 12. Offsets and lag

- Each group stores, per partition, the offset of the **next** event it will read. Kafka keeps these bookmarks in an internal topic (`__consumer_offsets`).

**T1** — describe the SMS group:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service
```

- Sample output:

```text
GROUP                TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID                                           HOST            CLIENT-ID
notification-service payments        0          4               4               0               console-consumer-00680b4a-b8a8-4225-b61c-6bb99117f21b /127.0.0.1      console-consumer
notification-service payments        1          9               9               0               console-consumer-00680b4a-b8a8-4225-b61c-6bb99117f21b /127.0.0.1      console-consumer
notification-service payments        2          2               2               0               console-consumer-57ed86d6-7762-4823-bd6c-35fd8da816f2 /127.0.0.1      console-consumer
```

| Column | Meaning |
| --- | --- |
| `CURRENT-OFFSET` | Group's bookmark: next offset it will read (committed every 5 s by default) |
| `LOG-END-OFFSET` | Offset the next new event will get = events written so far |
| `LAG` | `LOG-END-OFFSET − CURRENT-OFFSET` = events not yet processed by this group |
| `CONSUMER-ID` | Member that owns the partition now (`-` when nobody is connected) |

Describe the fraud group:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group fraud-check
```

- **Expected:** `Consumer group 'fraud-check' has no active members.` (its consumer stopped after 10 s), same offsets, `LAG 0`, `CONSUMER-ID -`.
- **Why:** offsets belong to the group, not to a running process. When fraud-check starts again it continues from these bookmarks.

## 13. Rebalance — watch the group change

- When a member joins or leaves, the group **rebalances**: the coordinator in the broker hands out the partitions again and raises the **generation** number.

Show the group's state:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service --state
```

- **Expected:** `ASSIGNMENT-STRATEGY range`, `STATE Stable`, `#MEMBERS 2`.

Show the last rebalance lines in the broker log:

```bash
grep notification-service /opt/kafka/logs/server.log | grep -E 'Preparing to rebalance|Stabilized' | tail -n 2 | cut -c1-260
```

**T3** — stop that member with **Ctrl+C**.

**T1** — read the log again:

```bash
grep notification-service /opt/kafka/logs/server.log | grep -E 'Preparing to rebalance|Stabilized' | tail -n 2 | cut -c1-260
```

- **Expected:** a new pair of lines: the reason is a `LeaveGroup` request and the generation goes up by one with one member fewer (`with 1 members` for you).
- Sample lines (from a run that had 4 members, so it ends `with 3 members`; your ids and numbers differ):

```text
[2026-11-15 08:24:54,435] INFO [GroupCoordinator id=1 topic=__consumer_offsets partition=39] Preparing to rebalance group notification-service in state PreparingRebalance with old generation 4 (reason: explicit `LeaveGroup` request for (console-consumer-e3047d60-2d1f-4e0f-8490-fff89d118fdd) members.). (org.apache.kafka.coordinator.group.GroupMetadataManager)
[2026-11-15 08:24:57,033] INFO [GroupCoordinator id=1 topic=__consumer_offsets partition=39] Stabilized group notification-service generation 5 with 3 members. (org.apache.kafka.coordinator.group.GroupMetadataManager)
```

See the new assignment:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service --members
```

- **Expected:** one member, `#PARTITIONS 3` — T2 now handles everything.

**T3** — start the member again (press the Up arrow, then Enter):

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group notification-service --formatter-property print.partition=true --formatter-property print.key=true
```

**T1** — read the log once more:

```bash
grep notification-service /opt/kafka/logs/server.log | grep -E 'Preparing to rebalance|Stabilized' | tail -n 2 | cut -c1-260
```

- **Expected:** reason `Adding new member console-consumer-…`, then `Stabilized group notification-service generation N with 2 members.`
- Sample lines:

```text
[2026-11-15 08:11:03,391] INFO [GroupCoordinator id=1 topic=__consumer_offsets partition=39] Preparing to rebalance group notification-service in state PreparingRebalance with old generation 1 (reason: Adding new member console-consumer-57ed86d6-7762-4823-bd6c-35fd8da816f2 with group instance id null; client reason: need to re-join with the given member-id: …)
[2026-11-15 08:11:05,797] INFO [GroupCoordinator id=1 topic=__consumer_offsets partition=39] Stabilized group notification-service generation 2 with 2 members. (org.apache.kafka.coordinator.group.GroupMetadataManager)
```

- **Why it matters:** during a rebalance the group pauses for a few seconds. Members that keep crashing and rejoining cause repeated pauses — a "rebalance storm" that shows up as many quickly rising generations in `server.log`.

## 14. Build a backlog and watch it drain

- Lag grows when events arrive faster than the group reads them — for example when every member is stopped.

**T2 and T3** — stop both SMS senders with **Ctrl+C**.

**T1** — confirm the group is empty:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service --state
```

- **Expected:** `Consumer group 'notification-service' has no active members.` and `STATE Empty`, `#MEMBERS 0`.
- `server.log` now ends with `Group notification-service with generation N is now empty.`

**T2** — watch the lag every 5 seconds:

```bash
watch -n 5 kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service
```

**T1** — keep paying: 100 payments a second for 30 seconds:

```bash
for i in $(seq 1 30); do ~/lab/kafka/gen-payments.sh 100; sleep 1; done | kafka-console-producer.sh --bootstrap-server localhost:9092 --topic payments --reader-property parse.key=true --reader-property key.separator=:
```

- **Expected (T2):** `LOG-END-OFFSET` and `LAG` climb every 5 seconds; `CURRENT-OFFSET` does not move.
- Make T2 wide (about 160 columns) or the table lines wrap.
- Sample, three snapshots of `PARTITION CURRENT-OFFSET LOG-END-OFFSET LAG`:

```text
0 1193 1412 219      0 1193 1707 514      0 1193 1949 756
1 1822 2195 373      1 1822 2647 825      1 1822 3058 1236
2 1000 1208 208      2 1000 1461 461      2 1000 1708 708
```

**T3** — start one SMS sender, without printing every event:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group notification-service > /dev/null
```

- **Expected (T2):** within a few seconds `CURRENT-OFFSET` catches up with `LOG-END-OFFSET` and `LAG` is `0` on all three partitions — no event was lost, the backlog simply waited in the log.
- Leave T3 running for the next step; stop `watch` in T2 with **Ctrl+C**.

## 15. Partition imbalance — hot key and idle member

- Lag per partition tells you **where** the work piles up.

**T3** — stop the SMS sender with **Ctrl+C**.

**T1** — one very busy account: 2,000 payments with the same key:

```bash
~/lab/kafka/gen-payments.sh 2000 acc-1001 | kafka-console-producer.sh --bootstrap-server localhost:9092 --topic payments --reader-property parse.key=true --reader-property key.separator=:
```

Describe the group:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service
```

- **Expected:** `LAG 2000` on partition 1 only; partitions 0 and 2 have `LAG 0`.
- Sample output:

```text
GROUP                TOPIC           PARTITION  CURRENT-OFFSET  LOG-END-OFFSET  LAG             CONSUMER-ID     HOST            CLIENT-ID
notification-service payments        0          2030            2030            0               -               -               -
notification-service payments        1          3210            5210            2000            -               -               -
notification-service payments        2          1775            1775            0               -               -               -
```

- **Why:** one key always maps to one partition, so one member does all the work for a hot account. Adding members does not help that partition — that is the price of keeping per-key order.

Start four SMS senders in the background (one group, three partitions):

```bash
for n in 1 2 3 4; do kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group notification-service --command-property client.id=sms-$n > /dev/null 2>&1 & sleep 3; done
```

Wait for the group to settle, then list the members:

```bash
sleep 15; kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service --members
```

- **Expected:** four members; one shows `#PARTITIONS 0`.
- Sample output:

```text
GROUP                CONSUMER-ID                                HOST            CLIENT-ID       #PARTITIONS
notification-service sms-4-7d809ce5-042f-4503-b761-081da866210e /127.0.0.1      sms-4           0
notification-service sms-3-4ea364f0-cd0c-4d44-811c-be053f79cefc /127.0.0.1      sms-3           1
notification-service sms-1-8651f988-9f86-4cf6-9230-41023733c387 /127.0.0.1      sms-1           1
notification-service sms-2-fe0fb566-0585-4dea-a262-d7d3fff76d65 /127.0.0.1      sms-2           1
```

- **Why:** a partition is read by at most one member of a group. More members than partitions = idle members (a standby, not extra speed).

Count the rebalances these four joins caused:

```bash
grep 'Stabilized group notification-service' /opt/kafka/logs/server.log | tail -n 4 | cut -c1-170
```

- **Expected:** four lines, generation rising by one each time, `with 1 members` … `with 4 members`.

Stop all four background senders:

```bash
pkill -f 'group notification-service'
```

- `pkill` sends SIGTERM; each consumer leaves the group cleanly (`LeaveGroup` in `server.log`).

## 16. Reset offsets — replay on purpose

- Moving a group's offset back makes it **read the same events again** (replay); moving it forward makes it **skip** events. Only the group's bookmark changes, never the data.
- Rule: the group must have **no running members**, and you always run `--dry-run` before `--execute`.

**T2** — start one SMS sender:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group notification-service > /dev/null
```

**T1** — try a reset while the group is active:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group notification-service --topic payments --reset-offsets --to-earliest --execute
```

- **Expected:** refused, nothing changed.
- Sample line:

```text
Error: Assignments can only be reset if the group 'notification-service' is inactive, but the current state is Stable.
```

**T2** — stop the sender with **Ctrl+C**.

**T1** — plan a reset to the first offset:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group notification-service --topic payments --reset-offsets --to-earliest --dry-run
```

- **Expected:** `NEW-OFFSET 0` for partitions 0, 1, 2. Nothing is changed yet.
- Without `--dry-run` or `--execute` the tool only plans, and warns: `WARN: No action will be performed as the --execute option is missing. In version 5.0, this command will require either --dry-run or --execute to be specified.`

Plan "go back 5 events per partition":

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group notification-service --topic payments --reset-offsets --shift-by -5 --dry-run
```

Apply it:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group notification-service --topic payments --reset-offsets --shift-by -5 --execute
```

Check the lag:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service
```

- **Expected:** `LAG 5` on each partition.

Replay those 15 events with partition and offset:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group notification-service --timeout-ms 10000 --formatter-property print.partition=true --formatter-property print.offset=true
```

- **Expected:** 5 events per partition, then `Processed a total of 15 messages`.
- Sample lines:

```text
Partition:0	Offset:2025	{"event":"PaymentCompleted","id":"PAY-082541-84","amount":500}
Partition:2	Offset:1770	{"event":"PaymentCompleted","id":"PAY-082541-79","amount":500}
Partition:1	Offset:5205	{"event":"PaymentCompleted","id":"PAY-082606-1996","amount":500}
```

- **Warning:** the SMS service would send those 15 SMS again. Replay is safe only when the consumer can handle duplicates (for example by checking the payment id).

### Reset by time — and the time-zone trap

- `--to-datetime` moves to the first event written **at or after** a time. The format is `YYYY-MM-DDThh:mm:ss.sss`, optionally followed by a zone such as `+05:30`.
- **A time without a zone is read as UTC**, even when your laptop is set to IST.

Show your laptop's time zone offset:

```bash
date +%:z
```

Store "20 minutes ago" in the form Kafka reads, **with** your zone:

```bash
START=$(date -d '-20 min' +%Y-%m-%dT%H:%M:%S.000%:z); echo $START
```

Plan the reset with the zone:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group notification-service --topic payments --reset-offsets --to-datetime $START --dry-run
```

Plan the same reset **without** the zone (the common mistake):

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group notification-service --topic payments --reset-offsets --to-datetime ${START%+*} --dry-run
```

- `${START%+*}` is the same text with the `+05:30` cut off.
- **Expected on an IST laptop:** with the zone, `NEW-OFFSET` values point at the first events of the last 20 minutes (the step 14 backlog).
- If you sent no events in those 20 minutes, both commands print the `empty` warning — use `-60 min` instead. Without the zone, the tool reads the time as 5½ hours in the future and prints `Warn: Partition 0 from topic payments is empty. Falling back to latest known offset.` for each partition — it would skip to the end, not replay.
- Sample output (IST laptop, same `START` with and without the zone):

```text
GROUP                TOPIC           PARTITION  NEW-OFFSET
notification-service payments        0          1193
notification-service payments        2          1000
notification-service payments        1          1822

Warn: Partition 0 from topic payments is empty. Falling back to latest known offset.
...
notification-service payments        0          2030
notification-service payments        2          1775
notification-service payments        1          5215
```

- If `date +%:z` prints `+00:00` (laptop on UTC), both commands give the same answer.
- The milliseconds are required: `2026-11-15T13:50:00+05:30` fails with `java.text.ParseException: Unparseable date`; `2026-11-15T13:50:00.000+05:30` works.

Leave the SMS group at the end of the topic:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group notification-service --topic payments --reset-offsets --to-latest --execute
```

| Reset option | Moves the bookmark to |
| --- | --- |
| `--to-earliest` / `--to-latest` | First / last offset still in the log |
| `--shift-by -N` | N events back (positive N = skip forward) |
| `--to-offset N` | Exactly offset N |
| `--to-datetime T` | First event at or after time T (UTC unless T has a zone) |
| `--by-duration PT10M` | First event in the last 10 minutes |

## 17. Retention — how long events stay

- Kafka deletes old events by **time or size**, whole segment files at a time — not when they are read.

Show settings changed on this topic (none yet):

```bash
kafka-configs.sh --bootstrap-server localhost:9092 --describe --topic payments
```

Show the effective retention settings:

```bash
kafka-configs.sh --bootstrap-server localhost:9092 --describe --all --topic payments | grep -E ' (retention.ms|retention.bytes|segment.bytes|cleanup.policy)='
```

- **Expected:** `retention.ms=604800000` (7 days in milliseconds), `retention.bytes=-1` (no size limit), `segment.bytes=1073741824` (1 GB files), `cleanup.policy=delete`.
- Sample output:

```text
  cleanup.policy=delete sensitive=false synonyms={DEFAULT_CONFIG:log.cleanup.policy=delete}
  retention.bytes=-1 sensitive=false synonyms={DEFAULT_CONFIG:log.retention.bytes=-1}
  retention.ms=604800000 sensitive=false synonyms={}
  segment.bytes=1073741824 sensitive=false synonyms={STATIC_BROKER_CONFIG:log.segment.bytes=1073741824, DEFAULT_CONFIG:log.segment.bytes=1073741824}
```

Show the broker-wide values from `server.properties`:

```bash
kafka-configs.sh --bootstrap-server localhost:9092 --describe --all --broker 1 | grep -E ' (log.retention.hours|log.retention.check.interval.ms|log.dirs)='
```

- **Expected:** `log.dirs=/var/lib/kafka`, `log.retention.hours=168`, `log.retention.check.interval.ms=300000` (Kafka looks for expired segments every 5 minutes).

Look at one partition on disk:

```bash
sudo ls -l /var/lib/kafka/payments-0
```

- Sample output:

```text
-rw-r--r-- 1 kafka kafka 10485760 Nov 15 08:25 00000000000000000000.index
-rw-r--r-- 1 kafka kafka   164099 Nov 15 08:25 00000000000000000000.log
-rw-r--r-- 1 kafka kafka 10485756 Nov 15 08:25 00000000000000000000.timeindex
-rw-r--r-- 1 kafka kafka        8 Nov 15 08:09 leader-epoch-checkpoint
-rw-r--r-- 1 kafka kafka       43 Nov 15 08:09 partition.metadata
```

| File | Holds |
| --- | --- |
| `00000000000000000000.log` | The events (segment starting at offset 0) |
| `.index` | Offset → position in the `.log` file |
| `.timeindex` | Time → offset (used by `--to-datetime`) |

Show disk use of the three partitions:

```bash
sudo du -sh /var/lib/kafka/payments-0 /var/lib/kafka/payments-1 /var/lib/kafka/payments-2
```

- The active segment is never deleted. With 1 GB segments and little traffic, everything here stays until a segment is full **and** older than 7 days.
- **Why it matters:** you can replay only events still inside retention. If a consumer is down longer than retention, the events it missed are gone — monitor lag before that happens.
- `/var/lib/kafka` must have room for 7 days of traffic: watch it with `df -h /var/lib/kafka`.

## 18. Fault exercise A — Kafka is stopped

**Break** — stop the broker:

```bash
sudo systemctl stop kafka
```

**Observe** — the service:

```bash
systemctl is-active kafka
```

The ports:

```bash
sudo ss -lntp | grep -E ':909[23] '
```

Try to publish one payment (wait for it — about one minute):

```bash
time (echo 'acc-1001:{"event":"PaymentCompleted","id":"PAY-DOWN-1"}' | kafka-console-producer.sh --bootstrap-server localhost:9092 --topic payments --reader-property parse.key=true --reader-property key.separator=:)
```

- **Expected:** `inactive`; no listener; the producer prints a WARN line every second, then after **60 s** the final error.
- Sample lines:

```text
[2026-11-15 08:28:14,744] WARN [Producer clientId=console-producer] Connection to node -1 (localhost/127.0.0.1:9092) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
[2026-11-15 08:29:14,618] ERROR Error when sending message to topic payments with key: 8 bytes, value: 46 bytes with error: (org.apache.kafka.clients.producer.internals.ErrorLoggingCallback)
org.apache.kafka.common.errors.TimeoutException: Topic payments not present in metadata after 60000 ms.
real	1m1.038s
```

- The 60 s is the producer's `max.block.ms` default. The console producer still exits with status 0 — read the output, not only the exit code. **That payment event was not stored.**

Start a consumer for 40 seconds:

```bash
timeout 40 kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group notification-service
```

- **Expected:** no error and no end — only the same `Connection to node -1 … could not be established` WARN about once a second until `timeout` stops it. Consumers keep retrying forever; a real service would look "running but idle".

Try an admin command:

```bash
time kafka-topics.sh --bootstrap-server localhost:9092 --list
```

- **Expected:** after **60 s**: `Error while executing topic command : Timed out waiting for a node assignment. Call: listTopics`. (`kafka-consumer-groups.sh --describe` gives up after 30 s with `Timed out waiting for a node assignment. Call: describeConsumerGroups(api=FIND_COORDINATOR)`.)

Read the end of the broker log:

```bash
tail -n 3 /opt/kafka/logs/server.log | cut -c1-160
```

- **Expected:** the last lines are a clean shutdown (`App info kafka.server for 1 unregistered`), no ERROR — someone stopped it.

**Recover** — start Kafka:

```bash
sudo systemctl start kafka
```

Wait until the journal shows a fresh start line:

```bash
until sudo journalctl -u kafka --since '2 min ago' --no-pager | grep -q 'Kafka Server started'; do sleep 2; done; sudo journalctl -u kafka --since '2 min ago' --no-pager | grep 'Kafka Server started'
```

- The broker writes the same lines to the journal and to `server.log`; the journal's `--since` keeps you from matching the **old** start line.

**Verify** — the topic is back:

```bash
kafka-topics.sh --bootstrap-server localhost:9092 --list
```

The SMS group kept its offsets:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service
```

- **Expected:** `__consumer_offsets` and `payments`; the SMS group with the same offsets as before the stop. Data and bookmarks are on disk, so a restart loses nothing — only the payment sent while Kafka was down is missing.

## 19. Fault exercise B — the SMS service is down

- Scenario: the notification service crashed at lunchtime; payments kept coming.

**Break** — make sure no SMS sender runs:

```bash
pkill -f 'group notification-service'; kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service --state
```

Payments continue — 500 of them:

```bash
~/lab/kafka/gen-payments.sh 500 | kafka-console-producer.sh --bootstrap-server localhost:9092 --topic payments --reader-property parse.key=true --reader-property key.separator=:
```

**Observe** — the group's lag:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service
```

- **Expected:** `has no active members`, `CONSUMER-ID -`, and `LAG` adding up to 500 over the three partitions.
- **Diagnosis:** lag growing + no members = the consumer is down (not Kafka). Lag growing **with** members = consumers too slow, or one hot partition.

Check fraud-check, which was not affected by the SMS outage:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group fraud-check
```

- **Expected:** fraud-check also has lag (it is not running either), but its bookmarks are separate from the SMS group's — each group catches up on its own.

**Recover** — **T2**, start the SMS sender again:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group notification-service --formatter-property print.key=true
```

- **Expected:** T2 prints the 500 waiting payments quickly, then waits for new ones.

**Verify** — **T1**:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service
```

- **Expected:** `LAG 0` on all three partitions and a `CONSUMER-ID` on each. No payment was lost, only delayed.
- Leave T2 running.

## 20. Fault exercise C — wrong bootstrap port

- Scenario: a developer copied the wrong port into the fraud service's settings.

**Break** — point a tool at port 9029 (nothing listens there):

```bash
time timeout 30 kafka-topics.sh --bootstrap-server localhost:9029 --list
```

**Observe:**

- **Expected:** many WARN lines with the **port you typed**, until `timeout` stops it after 30 s (without `timeout` the tool gives up after 60 s with `Timed out waiting for a node assignment. Call: listTopics`).
- Sample line:

```text
WARN [AdminClient clientId=adminclient-1] Connection to node -1 (localhost/127.0.0.1:9029) could not be established. Node may not be available. (org.apache.kafka.clients.NetworkClient)
```

Point it at the controller port 9093 instead:

```bash
time timeout 30 kafka-topics.sh --bootstrap-server localhost:9093 --list
```

- **Expected:** a fast failure (about 2 s), because something answers on 9093 — but it is the controller, not a broker.
- Sample lines:

```text
WARN [AdminClient clientId=adminclient-1] The remote node is not a BROKER that supports the METADATA api. (org.apache.kafka.clients.admin.internals.AdminMetadataManager)
Error while executing topic command : The node does not support METADATA
```

Check which ports Kafka really uses:

```bash
grep -E '^(listeners|advertised.listeners)=' /opt/kafka/config/server.properties
```

**Recover** — use the client port 9092:

```bash
kafka-topics.sh --bootstrap-server localhost:9092 --list
```

**Verify:** `__consumer_offsets` and `payments` print at once.

- **Lesson:** clients always use the **broker** listener (9092). 9093 is only for the controller. The WARN line names the host and port the client really tried — read it before blaming Kafka.

## 21. Exercise — replay a time window for fraud-check

- Scenario: the fraud rules were wrong for the last few minutes. After the fix, fraud-check must re-check every payment since a given time. SMS must **not** be re-sent, so only the `fraud-check` group moves.

Note the start of the window (with your zone):

```bash
START=$(date +%Y-%m-%dT%H:%M:%S.000%:z); echo $START
```

Five payments arrive inside the window:

```bash
~/lab/kafka/gen-payments.sh 5 acc-4004 | kafka-console-producer.sh --bootstrap-server localhost:9092 --topic payments --reader-property parse.key=true --reader-property key.separator=:
```

Bring fraud-check up to date first (it reads everything up to now, then stops):

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group fraud-check --timeout-ms 10000 > /dev/null
```

Check it has no lag:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group fraud-check
```

Plan the reset to the window start:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group fraud-check --topic payments --reset-offsets --to-datetime $START --dry-run
```

Apply it:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group fraud-check --topic payments --reset-offsets --to-datetime $START --execute
```

Replay the window, with the time each event was written:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group fraud-check --timeout-ms 10000 --formatter-property print.timestamp=true --formatter-property print.key=true
```

- **Expected:** exactly the 5 `acc-4004` payments, each with `CreateTime:` (milliseconds since 1970), then `Processed a total of 5 messages`.
- The plan and the reset print `Warn: Partition 0 … is empty. Falling back to latest known offset.` for partitions 0 and 2: no event arrived there since `START` (all `acc-4004` events are in partition 1). That is correct here.
- Sample lines:

```text
CreateTime:1794736475235	acc-4004	{"event":"PaymentCompleted","id":"PAY-152433-1","amount":500}
CreateTime:1794736475250	acc-4004	{"event":"PaymentCompleted","id":"PAY-152433-5","amount":500}
Processed a total of 5 messages
```

Prove SMS was not touched:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service
```

- **Expected:** SMS group `LAG 0` with its member from T2 still attached; the reset changed only fraud-check.
- To stop at an **end** time as well, compare `CreateTime` and ignore events after it — the console consumer has no "until" option.

## 22. Handoff

- Leave Kafka running with topic `payments`, both groups at `LAG 0`, and stop the console consumers.

**T2** — stop the SMS sender with **Ctrl+C**. Close T2 and T3.

**T1** — check the services:

```bash
systemctl is-active kafka rabbitmq-server tomcat payment-kong
```

Check the topic:

```bash
kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic payments
```

Check the SMS group:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service
```

Check the fraud group:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group fraud-check
```

Check memory:

```bash
free -m
```

Save the evidence:

```bash
{ date -Is; systemctl is-active kafka; kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic payments; kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service; kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group fraud-check; } 2>&1 | tee ~/lab/evidence/day2/lab2-kafka.txt
```

- **Expected:** four `active` lines; `payments` with 3 partitions, `Leader: 1`, `Isr: 1`; both groups `has no active members` with `LAG 0`.
- If the laptop is short of memory before Lab 3, `sudo systemctl stop kafka` is safe — data and offsets stay on disk; start it again with `sudo systemctl start kafka`.
- Continue to [Lab 3](03-security.md).
- References: [Kafka quickstart](https://kafka.apache.org/quickstart), [Kafka operations](https://kafka.apache.org/documentation/#operations), [consumer groups tool](https://kafka.apache.org/documentation/#basic_ops_consumer_group).

## Check yourself

1. After a RabbitMQ consumer acks a message it is gone. What happens to a Kafka event after `notification-service` reads it, and what decides when it is finally deleted?
2. Apache's `.sha512` file made `sha512sum -c` print `no properly formatted checksum lines found`. Was the download bad? How do you check it?
3. `systemctl is-active kafka` says `active` but `kafka-topics.sh --list` hangs. What do you check next, and which log line proves the broker is ready?
4. Payments for `acc-1001` must be processed in order. Why does using the account as the key guarantee this, and what is the cost when one account is very busy?
5. `notification-service` has 4 members and `payments` has 3 partitions. What does the fourth member do? What would you change to make all four work?
6. `kafka-consumer-groups.sh --describe` shows `LAG` 0, 0, 2000 with no `CONSUMER-ID`. What is wrong, and what is your first fix?
7. You run `--reset-offsets --to-earliest --execute` and get `Assignments can only be reset if the group … is inactive`. Why does Kafka refuse, and what do you do?
8. On an IST laptop you reset fraud-check with `--to-datetime 2026-11-15T10:00:00.000` to replay from 10:00 local time. It printed `Falling back to latest known offset` and replayed nothing. Why, and what is the correct value?
