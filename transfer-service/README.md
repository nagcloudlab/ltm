# transfer-service — a Java Kafka producer

- A small Java program that plays the bank's **transfer-service**.
- Every money transfer becomes one **TransferCompleted** event on the Kafka topic **`transfers`**.
- **Key** = sender's account number, so all transfers from one account land in the same partition, in order.
- **Value** = the transfer as one line of JSON.
- **Needs:** Kafka running on `localhost:9092`, with the Kafka tools on your PATH.

## 1. Install the build tools

Install JDK 21 and Maven:

```bash
sudo apt install -y openjdk-21-jdk-headless maven
```

## 2. Build the jar

Go to the project:

```bash
cd ~/ltm/transfer-service
```

Build it (the first build downloads libraries):

```bash
mvn -q package
```

- **Expected:** `target/transfer-service.jar`, about 20 MB.

## 3. Create the topic

Create `transfers` with 3 partitions:

```bash
kafka-topics.sh --bootstrap-server localhost:9092 --create --topic transfers --partitions 3 --replication-factor 1
```

- Create the topic first: if it is missing, Kafka creates it automatically with only 1 partition.

## 4. Run the producer

Send 10 transfers, one per second:

```bash
java -jar target/transfer-service.jar
```

- Sample output:

```text
transfer-service: sending 10 transfers to topic 'transfers' on localhost:9092
SENT     TRF-fc3987f9 key=ACC-1002 partition=2 offset=0
SENT     TRF-b1d27c80 key=ACC-1008 partition=0 offset=0
SENT     TRF-a41a4445 key=ACC-1004 partition=1 offset=0
```

Send 20 transfers with no pause:

```bash
java -jar target/transfer-service.jar 20 0
```

Read the events back:

```bash
kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic transfers --from-beginning --formatter-property print.key=true --formatter-property print.partition=true
```

- Sample line:

```text
Partition:2	ACC-1002	{"event":"TransferCompleted","transferId":"TRF-fc3987f9","from":"ACC-1002","to":"ACC-1007","amount":1800,"currency":"INR","time":"2026-11-16T09:54:01.908872094Z"}
```

- Stop it with Ctrl+C.

## Settings

| Setting | How to change | Default |
| --- | --- | --- |
| Number of transfers | first argument | `10` |
| Pause between transfers (ms) | second argument | `1000` |
| Kafka address | `KAFKA_BOOTSTRAP` environment variable | `localhost:9092` |
| Topic | `TRANSFER_TOPIC` environment variable | `transfers` |

- If Kafka is down, each transfer prints `FAILED … Topic transfers not present in metadata after 10000 ms.` after about 10 seconds.
