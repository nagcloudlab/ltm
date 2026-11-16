# notification-service — a Java Kafka consumer

- A small Java program that plays the bank's **notification-service**.
- It reads **TransferCompleted** events from the Kafka topic **`transfers`** (written by [transfer-service](../transfer-service/README.md)) and prints one SMS per transfer.
- It joins the consumer group **`notification-service`**: run two copies and Kafka splits the 3 partitions between them.
- It saves its position (commits the offset) only after the SMS lines are printed.
- **Needs:** Kafka on `localhost:9092`, the topic `transfers`, and transfer-service built.

## 1. Build the jar

Go to the project:

```bash
cd ~/ltm/notification-service
```

Build it:

```bash
mvn -q package
```

- **Expected:** `target/notification-service.jar`, about 20 MB.

## 2. Run the consumer

**Terminal A** — start notification-service:

```bash
java -jar ~/ltm/notification-service/target/notification-service.jar
```

**Terminal B** — send 10 transfers:

```bash
java -jar ~/ltm/transfer-service/target/transfer-service.jar
```

- **Expected:** terminal A prints one `SMS` line per transfer, with its partition (`p`) and offset (`o`).
- Sample output:

```text
notification-service: reading topic 'transfers' on localhost:9092 as group 'notification-service' (Ctrl+C to stop)
SMS      p2/o0    to ACC-1002: Rs 1800 sent to ACC-1007 (TRF-fc3987f9)
SMS      p0/o0    to ACC-1008: Rs 2400 sent to ACC-1003 (TRF-b1d27c80)
```

## 3. Check the group's lag

Describe the group:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notification-service
```

- **Expected:** one line per partition; `LAG` is `0` when every event has been handled.

## 4. Two copies share the work

**Terminal C** — start a second copy:

```bash
java -jar ~/ltm/notification-service/target/notification-service.jar
```

**Terminal B** — send 20 transfers with no pause:

```bash
java -jar ~/ltm/transfer-service/target/transfer-service.jar 20 0
```

- **Expected:** terminals A and C both print SMS lines, each for different partitions.
- Stop one copy with Ctrl+C and send again: the other copy takes over all partitions.

## Settings

| Setting | Environment variable | Default |
| --- | --- | --- |
| Kafka address | `KAFKA_BOOTSTRAP` | `localhost:9092` |
| Topic | `TRANSFER_TOPIC` | `transfers` |
| Consumer group | `GROUP_ID` | `notification-service` |

- A new group starts from the oldest event (`auto.offset.reset=earliest`); an existing group continues from its saved offset.
