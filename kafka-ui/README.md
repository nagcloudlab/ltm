# Kafka UI — a web page for your Kafka broker

- [Kafka UI](https://github.com/provectus/kafka-ui) (provectus, v0.7.1): one Java jar that shows brokers, topics, partitions, messages and consumer groups in the browser.
- **Needs:** Java 17 or newer, and Kafka running on `localhost:9092`.
- Web page: **http://localhost:8090** (8080 is Tomcat's port in the labs).

## Files

| File | What it is |
| --- | --- |
| `lib/kafka-ui-api-v0.7.1.jar` | The application (about 95 MB, downloaded, not in git) |
| `application.yml` | Settings: web port 8090, one cluster `local` at `localhost:9092`, no login |

## 1. Download the jar

- Skip this step if `lib/kafka-ui-api-v0.7.1.jar` is already there.

Go to the folder:

```bash
cd ~/ltm/kafka-ui
```

Create the `lib` folder:

```bash
mkdir -p lib
```

Download the jar:

```bash
curl -L -o lib/kafka-ui-api-v0.7.1.jar https://github.com/provectus/kafka-ui/releases/download/v0.7.1/kafka-ui-api-v0.7.1.jar
```

Check its size:

```bash
ls -l lib/kafka-ui-api-v0.7.1.jar
```

- **Expected:** `94975596` bytes.

## 2. Check Kafka is running

List the topics:

```bash
kafka-topics.sh --bootstrap-server localhost:9092 --list
```

- **Expected:** your topics (for example `transfers`), and no connection errors.

## 3. Start Kafka UI

Go to the folder:

```bash
cd ~/ltm/kafka-ui
```

Start it (leave this terminal open):

```bash
java -Dspring.config.additional-location=./application.yml --add-opens java.rmi/javax.rmi.ssl=ALL-UNNAMED -jar ./lib/kafka-ui-api-v0.7.1.jar
```

| Part | Meaning |
| --- | --- |
| `-Dspring.config.additional-location=./application.yml` | Read our settings file |
| `--add-opens java.rmi/javax.rmi.ssl=ALL-UNNAMED` | Lets the jar use an internal Java class it needs on Java 17+ |
| `-jar ./lib/kafka-ui-api-v0.7.1.jar` | Run the application |

- **Expected:** a few seconds later, `Started KafkaUiApplication in … seconds`.
- A `WARN … Authentication is disabled` line is expected: `application.yml` turns the login off for the classroom.

## 4. Open the web page

Check it answers:

```bash
curl -s http://localhost:8090/api/clusters
```

- **Expected:** `"name":"local"` and `"status":"online"` with `"brokerCount":1`.

Open in the browser:

```text
http://localhost:8090
```

| Menu | What you see |
| --- | --- |
| Dashboard | Cluster `local`: online, broker count, partitions |
| Brokers | Broker `1` at `localhost:9092`, partitions it leads |
| Topics | Topics, partitions, message counts; **Messages** tab shows each event's key, partition, offset and value |
| Consumers | Groups such as `notification-service`: members, state and **lag** per partition |

## 5. Try it with the transfer services

Send 10 transfers:

```bash
java -jar ~/ltm/transfer-service/target/transfer-service.jar 10 0
```

- In the UI: **Topics → transfers → Messages**: the 10 `TransferCompleted` events, with key `ACC-…` and their partition.

Start the consumer in another terminal:

```bash
java -jar ~/ltm/notification-service/target/notification-service.jar
```

- In the UI: **Consumers → notification-service**: state `STABLE`, 1 member, lag `0`.
- Stop the consumer (Ctrl+C), send more transfers, and watch the lag grow; start it again and watch the lag return to `0`.

## 6. Stop Kafka UI

- Press Ctrl+C in the terminal from step 3.

## If it fails

| Symptom | Check |
| --- | --- |
| `Port 8090 was already in use` | Another program uses 8090: change `server.port` in `application.yml` |
| Cluster shows **offline** | Kafka is not running, or not on `localhost:9092`: change `bootstrapServers` |
| `UnsupportedClassVersionError` | Java is older than 17: `java -version` |
| Page loads but no topics | Normal for a new broker: create a topic or send transfers |

- To use another broker address, edit `bootstrapServers` in `application.yml` and restart.
- Classroom settings only: no login and `readOnly: false` (anyone who opens the page can create and delete topics).
