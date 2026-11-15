# Ubuntu middleware labs, Day 2 — messaging and security

- Three incremental labs on the **same laptop** you used for Day 1: the payment stack keeps running, and you add messaging and security around it.
- Scripts and configuration stages are included. No application coding is required.
- Finish the [Day 1 labs](../middleware-labs/README.md) (Labs 1–5) first.

## Start

Go to the repository:

```bash
cd ~/ltm
```

Get the latest lab files:

```bash
git pull --ff-only
```

Enter the Day 2 folder:

```bash
cd ~/ltm/middleware-labs-day2
```

- Then follow [Day 2 start](00-day2-start.md) and the guides below in order.
- See also: [validation record](VALIDATION.md).

| Lab | Guide | What you add |
| --- | --- | --- |
| 1 | [RabbitMQ](01-rabbitmq.md) | Message broker, exchange and queues, publish/consume, acknowledgements, retries, dead letters, monitoring, recovery |
| 2 | [Kafka](02-kafka.md) | Event log, topic and partitions, consumer groups, ordering by key, lag, rebalances, offset reset and replay |
| 3 | [Security](03-security.md) | Basic auth and API keys revisited, JWT, Kong JWT plugin, OAuth token issuer, TLS certificate chain, certificate errors |

- After the labs: compare with the [answers](04-answers.md).

## The project grows in place

```text
Day 1 stack (keeps running):
  curl -> Apache :80 / Nginx :8081 -> Tomcat 127.0.0.1:8080 -> payment.war
  curl -> Kong 127.0.0.1:8000 -> Tomcat

Lab 1: payment events -> RabbitMQ :5672 (exchange payments -> queues sms, fraud; dead letters -> sms.dlq)
Lab 2: payment events -> Kafka :9092 (topic payments, groups notification-service, fraud-check)
Lab 3: curl + JWT -> Kong /api/v2/payment -> Tomcat;  token issuer 127.0.0.1:9000;  Nginx HTTPS :443
```

- Small Python scripts stand in for the payment, notification and fraud-check services.
- Everything stays on your laptop. Sample data and classroom secrets only; no real money.

## Repository layout

- `project-files/rabbitmq/`: producer and consumer scripts for Lab 1.
- `project-files/kafka/`: Kafka configuration, systemd unit and download checksum for Lab 2.
- `project-files/security/`: JWT, token issuer, certificate and TLS files for Lab 3.
- `project-files/kong/`: the next Kong configuration stages, after Day 1's `04-rate-limit.yml`.
- `project-files/SHA256SUMS`: checksums of the supplied files.

## Ports on your laptop after Day 2

| Port | Service |
| --- | --- |
| 80, 8081 | Apache, Nginx (Day 1) |
| 443 | Nginx HTTPS (Lab 3) |
| 127.0.0.1:8080 | Tomcat (Day 1) |
| 127.0.0.1:8000, 8001 | Kong proxy, admin (Day 1) |
| 5672, 15672 | RabbitMQ AMQP, management UI (Lab 1) |
| 127.0.0.1:9092, 9093 | Kafka broker, controller (Lab 2) |
| 127.0.0.1:9000 | Token issuer (Lab 3) |
