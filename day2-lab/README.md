# Day 2 lab material

Trainer material behind the Day 2 deck (Modules 9–13). These are the scripts, configs and notes used while building and testing the slides on Ubuntu 24.04 — **not yet student handouts**. Each `NOTES.md` lists what the slides assume is on the student VM, what was verified for real, and what was not.

| Folder | Module | Contents |
|---|---|---|
| `m09-messaging/` | 9 Messaging basics | `NOTES.md`; `tested-commands/` — Kafka 4.4 KRaft and RabbitMQ 3.12.1 setup scripts with their real output (`*.out`), the 202 stub app |
| `m10-broker-operations/` | 10 Kafka and RabbitMQ in operation | `NOTES.md`; `lab/` — `publish.py`, `sms-consumer.py`, `sms-noack.py`, `sms-poison.py`, `sms-rejectall.py` (need `python3-pika`, copy to `~/lab`); `tested-commands/` — demo scripts |
| `m11-security/` | 11 Authentication and API security | `NOTES.md`; `lab/` — JWT scripts, PyJWT checker, token issuer (port 9000), Kong jwt configs, CA/expired-cert scripts, Java `TlsCheck.java` |
| `m12-performance/` | 12 Configuration and performance | `NOTES.md`; `payment-app/` — payment app source (servlets + JSP) and built `payment.war` with `/payment/node`, `/whoami`, `/session`, `/db`, `/leak`, `/slow`, `/fail`, `/status` |
| `m13-troubleshooting/` | 13 Integrated troubleshooting | `NOTES.md`; `lab/` — Module 13 `kong.yml` + `kong.conf.additions`, Nginx site, `notification.py` (with `BUG` switch), `transfer.jsp` (202 + publish), case scripts, PKI script, IIS sample log |

## Student VM prerequisites (on top of Day 1)
- Packages: `openjdk-21-jdk-headless`, `rabbitmq-server`, `python3-pika`, `python3-jwt`, `jq`, `postgresql` (Module 12: database `paydb`, user `payapp`)
- Kafka 4.4.0 tarball in `/opt/kafka` (KRaft, `log.dirs=/var/lib/kafka`, systemd unit `kafka`)
- Shared names: topic `payments`; RabbitMQ exchange `payments` (type topic) → queue `sms` (key `payment.completed`); dead letters via policy `sms-dlx` → exchange `payments.dlx` (fanout) → queue `sms.dlq`; consumer groups `notification-service`, `fraud-check`
- Ports: Nginx HTTPS on **443** (Kong owns 8443/8444); token issuer 9000; second Tomcat 8082

## Notes
- The keys and certificates in `m11-security/lab/` (e.g. `issuer/private.pem`) are throwaway lab keys. Never reuse them anywhere real.
- `NOTES.md` files mention the slide generators (`gen2/…`) and raw captures; those stay with the deck build and are not in this repo.
- The tests ran in a Docker container standing in for the student VM; students' VMs need no Docker.
