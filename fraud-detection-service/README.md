# fraud-detection-service — a second Java Kafka consumer

- Reads the same **`transfers`** topic as [notification-service](../notification-service/README.md), but in its **own consumer group** `fraud-detection-service`, so it receives **every** event too.
- Two rules:
  - **HIGH_AMOUNT**: one transfer of Rs 4000 or more.
  - **VELOCITY**: more than 5 transfers from the same account within 10 seconds (one alert per account per window).
- VELOCITY keeps a small history per account. It works because the key is the account number: all events of one account land in one partition, so one consumer sees them all.
- Prints only alerts, plus `SUMMARY checked=… alerts=…` every 5 seconds.
- **Needs:** Kafka on `localhost:9092`, the topic `transfers`, and transfer-service built.

## 1. Build the jar

Go to the project:

```bash
cd ~/ltm/fraud-detection-service
```

Build it:

```bash
mvn -q package
```

## 2. Run it next to notification-service

**Terminal A** — fraud-detection-service:

```bash
java -jar ~/ltm/fraud-detection-service/target/fraud-detection-service.jar
```

**Terminal B** — notification-service:

```bash
java -jar ~/ltm/notification-service/target/notification-service.jar
```

**Terminal C** — 12 transfers, one per second:

```bash
java -jar ~/ltm/transfer-service/target/transfer-service.jar 12 1000
```

- **Expected (terminal A):** a `HIGH_AMOUNT` alert for each large transfer; no `VELOCITY` alerts at this speed.

```text
ALERT    HIGH_AMOUNT p0/o0     ACC-1007: Rs 4900 to ACC-1002 (TRF-165c51b7)
SUMMARY  checked=12 alerts=3
```

Now 300 transfers, 1 ms apart:

```bash
java -jar ~/ltm/transfer-service/target/transfer-service.jar 300 1
```

- **Expected (terminal A):** one `VELOCITY` alert per account.

```text
ALERT    VELOCITY    p2/o8     ACC-1003: 6 transfers in 10 s
```

- Terminal B prints an SMS for every transfer: both groups get all events.

## 3. Compare the two groups

Show both groups:

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --all-groups
```

- **Expected:** `fraud-detection-service` and `notification-service`, each with its own offsets for the same 3 partitions, and lag `0`.

## Settings

| Setting | Environment variable | Default |
| --- | --- | --- |
| Kafka address | `KAFKA_BOOTSTRAP` | `localhost:9092` |
| Topic | `TRANSFER_TOPIC` | `transfers` |
| Consumer group | `GROUP_ID` | `fraud-detection-service` |

- Rule limits are constants at the top of `FraudDetectionService.java`: `HIGH_AMOUNT`, `VELOCITY_MAX`, `VELOCITY_WINDOW`.
