# Day 2 start — check the Day 1 stack

- **Needs:** the same Ubuntu laptop with Day 1 Labs 1–5 completed
- **You build:** a verified starting point, updated lab files and the extra packages Day 2 uses

## 1. Prove the Day 1 stack still works

- Day 2 adds to this stack; fix anything broken here before you continue.

Check the four services:

```bash
systemctl is-active apache2 nginx tomcat payment-kong
```

Static portal through Apache:

```bash
curl -s http://portal.example.test/health.txt
```

Static portal through Nginx:

```bash
curl -s http://portal.example.test:8081/health.txt
```

Tomcat directly:

```bash
curl -s http://127.0.0.1:8080/payment/status
```

Through the gateway with the API key:

```bash
curl -s -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

- **Expected:** four `active` lines, `WEB PORTAL OK` twice, `Payment Service OK` twice.
- **If it fails:** a service after a reboot may need `sudo systemctl start <name>`; a 429 from Kong clears at the next minute.

## 2. Update the lab files

Go to the repository:

```bash
cd ~/ltm
```

Show local changes (should be empty):

```bash
git status --short
```

Get the latest files:

```bash
git pull --ff-only
```

Verify the Day 2 files:

```bash
cd ~/ltm/middleware-labs-day2/project-files && sha256sum -c SHA256SUMS
```

- **Expected:** every line ends in `OK`.
- **If it fails:** stop and compare with a partner; do not use `git reset --hard`.

## 3. Install the extra packages

- `python3-pika` talks to RabbitMQ, `python3-jwt` reads and signs tokens, `jq` pretty-prints JSON, and the JDK runs a small Java TLS check in Lab 3.

Refresh package lists:

```bash
sudo apt update
```

Install the Day 2 tools:

```bash
sudo apt install -y python3-pika python3-jwt jq openssl openjdk-21-jdk-headless
```

Check Python can load both libraries:

```bash
python3 -c 'import pika, jwt; print("pika", pika.__version__, "jwt", jwt.__version__)'
```

Check Java is still version 21:

```bash
java -version
```

- **Expected:** library versions print with no error; Java reports `21`.

## 4. Check the Day 2 ports are free

List listeners:

```bash
sudo ss -lntp
```

- **Expected:** nothing yet on 443, 5672, 15672, 9092, 9093 or 9000.
- **If a port is taken:** find the owner with `sudo ss -lntp 'sport = :<port>'` before you continue; do not stop unfamiliar services.

## 5. Start your Day 2 evidence notes

Create the evidence folder:

```bash
mkdir -p ~/lab/evidence/day2
```

Record the start time:

```bash
date -Is | tee ~/lab/evidence/day2/start-time.txt
```

- For every fault: command, status, timestamp, log line, failing component, recovery and successful retest.

**Ready:** go to [Lab 1 — RabbitMQ](01-rabbitmq.md).
