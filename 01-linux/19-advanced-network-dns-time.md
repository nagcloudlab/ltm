# 19 · Advanced: names, timings, time and certificates

**Time:** 35 min

**Practise on** your own lab VM. **Needs:** paysim from Topic 17 running. Internet access for 19.6 only.

**You will learn:** why `dig` and your app can disagree about a name, test a name without DNS using `curl --resolve`, split a slow request into DNS / connect / server time, read the server's clock and time zone, convert log times, and check when a TLS certificate expires.

---

## 19.1 · Two ways to look up a name

```bash
getent hosts ubuntu.com
dig +short ubuntu.com
resolvectl query ubuntu.com
```

| Tool | Reads `/etc/hosts`? | Asks DNS? | Same answer as your app? |
|---|---|---|---|
| `getent hosts` | **yes, first** | yes | **yes** |
| `dig` | no | yes, directly | not always |
| `resolvectl query` | yes | yes | yes |

- `dig` is in package **bind9-dnsutils** (installed on Ubuntu server).
- Programs (curl, Java, Apache) look up names the `getent` way: `/etc/hosts` first, then DNS.

## 19.2 · Break it: a wrong /etc/hosts line

Someone added a test entry for the core-banking server and forgot it:

```bash
sudo cp /etc/hosts /etc/hosts.bak
echo "10.9.9.9 core-banking.bank.internal" | sudo tee -a /etc/hosts
getent hosts core-banking.bank.internal
dig +short core-banking.bank.internal
curl -s -o /dev/null -w "%{http_code}\n" --max-time 3 http://core-banking.bank.internal:9443/
echo $?
```

- `getent` answers `10.9.9.9`: that is the address your app uses.
- `dig` answers nothing (the name is not in DNS): someone checking only with `dig` says "DNS is fine".
- `curl` prints `000` and `$?` is `28` = **timed out**: nothing at 10.9.9.9 answers.

| curl exit code | Means |
|---|---|
| 6 | could not resolve the name |
| 7 | connection refused |
| 28 | timed out |
| 35 / 60 | TLS / certificate problem |

Fix and verify:

```bash
sudo cp /etc/hosts.bak /etc/hosts
getent hosts core-banking.bank.internal || echo "not in /etc/hosts any more"
```

> When a name "resolves wrongly on one server only", read `/etc/hosts` on that server first.

## 19.3 · Test a site by name, without DNS: `curl --resolve`

```bash
curl -s --resolve portal.example.com:8085:127.0.0.1 http://portal.example.com:8085/health
```

- `--resolve name:port:ip` = "for this one command, `name` means `ip`".
- Use it to test a new server **before** DNS points to it, or to test one server behind a load balancer.

## 19.4 · Where does the time go? curl timings

```bash
curl -s -o /dev/null -w "dns=%{time_namelookup} connect=%{time_connect} first-byte=%{time_starttransfer} total=%{time_total}\n" http://127.0.0.1:8085/health
curl -s -o /dev/null -w "dns=%{time_namelookup} connect=%{time_connect} first-byte=%{time_starttransfer} total=%{time_total}\n" https://ubuntu.com/
```

All numbers are seconds **since the start**, so each one includes the one before:

```
start ── dns ──► connect ──► (TLS) ──► first-byte ──► total
          name     TCP open              server       last byte
          lookup                         thinking     received
```

| Big gap between | Look at |
|---|---|
| start → `dns` | DNS server slow or wrong |
| `dns` → `connect` | network, firewall, far away |
| `connect` → `first-byte` | the **server/app** is slow (a database, a full pool) |
| `first-byte` → `total` | large response or slow network |

## 19.5 · The server's clock and time zone

```bash
timedatectl
date
date -u
TZ=Asia/Kolkata date
```

| Line in `timedatectl` | Means |
|---|---|
| `Time zone: Etc/UTC (UTC, +0000)` | the server's zone: many servers use UTC |
| `System clock synchronized: yes` | the clock is set from a time server (NTP) |
| `NTP service: active` | `systemd-timesyncd` keeps it correct |

- Why it matters: logs from two servers with clocks 3 minutes apart tell the wrong story. TLS and logins can fail when a clock is far off.
- Change the zone (only with permission): `sudo timedatectl set-timezone Asia/Kolkata`.

Convert a log time between zones:

```bash
date -d "2026-08-24 03:43:14 UTC"
TZ=Asia/Kolkata date -d "2026-08-24 03:43:14 UTC"
TZ=UTC date -d 'TZ="Asia/Kolkata" 2026-08-24 09:13:14'
```

- `03:43:14 UTC` = `09:13:14 IST` (IST = UTC + 5:30): the moment PayBank's pool filled up.

## 19.6 · When does a certificate expire?

Make a test certificate valid for 7 days, then read it:

```bash
cd ~/practice
openssl req -x509 -newkey rsa:2048 -nodes -keyout lab.key -out lab.crt -days 7 -subj "/CN=portal.example.com"
openssl x509 -in lab.crt -noout -subject -issuer -enddate
openssl x509 -in lab.crt -noout -checkend 2592000
openssl x509 -in lab.crt -noout -checkend 86400
```

- The rows of dots and `+` while it runs = the key being generated: normal.
- `-enddate` → `notAfter=…`: the last valid moment (in GMT).
- `-checkend 2592000` = "will it expire within 30 days (2,592,000 s)?" → `Certificate will expire` (exit code 1). Good for a cron or timer alert.
- `-checkend 86400` = within 1 day? → `Certificate will not expire` (exit code 0).

Read the certificate of a live website:

```bash
echo | openssl s_client -connect ubuntu.com:443 -servername ubuntu.com 2>/dev/null | openssl x509 -noout -subject -enddate
```

- An expired certificate gives browsers a warning and curl exit code **60**. Middleware admins renew certificates **before** this date.

---

## Exercises

1. `dig` shows the right IP for `api.bank.internal`, but the app connects to an old IP. What do you check?
2. Test paysim as `payments.example.com` on port 8085 without changing any file.
3. A request takes 4.2 s. curl shows `connect=0.002 first-byte=4.150`. Network or server?
4. A log says `2026-08-24 03:43:14` and the server is in UTC. What time was that in India?
5. Will `lab.crt` still be valid in 3 days? Prove it with one command.

## Answers

1. `/etc/hosts` on that server (`getent hosts api.bank.internal`).
2. `curl -s --resolve payments.example.com:8085:127.0.0.1 http://payments.example.com:8085/health`.
3. The server: connecting took 2 ms, the answer took 4.1 s.
4. `TZ=Asia/Kolkata date -d "2026-08-24 03:43:14 UTC"` → 09:13:14 IST.
5. `openssl x509 -in ~/practice/lab.crt -noout -checkend 259200` → `Certificate will not expire`.
