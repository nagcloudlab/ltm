# Checks on the Day 2 materials

- Each lab was written from real runs on Ubuntu 24.04 with systemd (arm64 test machine), on top of the Day 1 stack: RabbitMQ 3.12.1 (Ubuntu package), Kafka 4.4.0 (KRaft, OpenJDK 21), Kong 3.9.1, Nginx 1.24.0, curl 8.5.0, OpenSSL 3.0.13, PyJWT 2.7.0, pika 1.2.0.
- Every **Expected** and **Sample** line in the guides is output that appeared in those runs.
- Not verified: browser views of the RabbitMQ management UI (checked through its HTTP API), the RabbitMQ memory alarm (limit shown only), a reboot.

## Run on a real amd64 VM (2026-11-15)

- **Machine:** Ubuntu 24.04.5 amd64, 2 vCPU, 4 GB RAM, no swap, clock on UTC, with the Day 1 stack running (Apache :80, Nginx :8081, Tomcat, Kong 3.9.1 stage 4).
- **What ran:** every command block of `00-day2-start.md`, `01-rabbitmq.md`, `02-kafka.md` and `03-security.md`, in order, as user `nag`.
- **Versions:** RabbitMQ 3.12.1 (Erlang/OTP 25), Kafka 4.4.0 on OpenJDK 21.0.13 (`/usr/lib/jvm/java-21-lab`), Kong 3.9.1, Nginx 1.24.0, Apache 2.4.58, curl 8.5.0, OpenSSL 3.0.13, Python 3.12.3, PyJWT 2.7.0, pika 1.2.0.
- **Result:** all four guides pass. Every lab ended in its handoff state: RabbitMQ queues empty with policy `sms-dlx`, Kafka running with both groups at `LAG 0`, Kong on stage 5, Nginx on 443, and the Day 1 checks still passing.

### Fixes made after this run

- `01-rabbitmq.md`: the log path now uses `rabbit@$(hostname -s).log`. When `hostname` prints a full name (`host.domain`), the old path did not exist; RabbitMQ names its log after the short host name.
- `01-rabbitmq.md` 13.4: after the disk alarm clears, `sms` may hold up to three extra messages, not exactly one. This run got all three (`sms  6`).
- `01-rabbitmq.md`: the sample connection lines now show `127.0.0.1`. On a stock Ubuntu `/etc/hosts`, `localhost` resolves only to IPv4, so `[::1]` does not appear.
- `02-kafka.md` step 10: whether partition 1 holds offsets 0–5 depends on where the three events without a key landed. This run put them in partition 2, so partition 1 had offsets 0–2.
- `02-kafka.md` step 15: the `cut` width went from 140 to 170. At 140 the `Stabilized … generation N with N members` lines were cut off before the generation number.

### Differences that need no change

- Downloading Kafka from archive.apache.org took about 7 minutes (about 300 KB/s). In a classroom, start this download early or copy the tarball from one machine; the checksum step still proves it is intact.
- Kafka took 8–9 s to print `Kafka Server started`. Memory with RabbitMQ, Kafka, Tomcat and Kong running: about 1.2 GB used, 2.6 GB available. With the broker and four background consumers: 1.6 GB used, 2.2 GB available. RSS: Kafka about 350–400 MB, Tomcat 150 MB, RabbitMQ 140 MB.
- The poison message was redelivered about 2,350 times a second (the guide's sample shows 13,600; the guide says yours will differ).
- On a UTC clock, the Lab 2 time-zone trap gives the same answer with and without the zone, as the guide says. The same commands with `TZ=Asia/Kolkata` behaved as described: with the zone the offsets were found; without it, `Falling back to latest known offset`. A time without milliseconds failed with `Unparseable date`.
- In Lab 2 step 16, every event was less than 20 minutes old because Kafka had just been installed, so the "20 minutes ago" plan gave `NEW-OFFSET 0`. That is correct: it is the first event after that time.
- After `systemctl reload nginx`, the new certificate was served about 0.4 s later. Commands sent faster than that saw the old certificate. The guide's "wait two seconds and repeat" note covers this.
- The Kong `sleep 5` after the reload was enough; the JWT tests gave the expected results at once.
- `/etc/hosts` is not managed by cloud-init on this VM, so the `portal.example.test` line stayed in place.

### Not verified

- The browser view of the RabbitMQ UI. The Lab 3 Basic-auth step ran with the sample password `s3cret`; the Day 1 password on this VM is unknown, so the request got a 401, but the header line appeared as described.
- `git pull` (skipped on this VM). A reboot.
