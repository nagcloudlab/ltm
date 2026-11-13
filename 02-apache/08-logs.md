# 08 · Logs: read them, count them, time them

**Time:** 45 min

**You will learn:** the two logs, every field of an access-log line, the error-log line, watching live, LogLevel, one-line answers to the common questions, adding response time, and log rotation.

---

## 08.1 · Two logs, two questions

| Log | Written | Answers |
|---|---|---|
| `access.log` | **every** request | **what** happened |
| `error.log` | only when something is wrong (and at start/stop) | **why** |

Each site with its own `ErrorLog`/`CustomLog` (topic 05) writes its own files: `portal-access.log`, `portal-error.log`.

```bash
ls -l /var/log/apache2/
```

## 08.2 · Generate some traffic

```bash
curl -s -o /dev/null http://localhost/
curl -s -o /dev/null http://localhost/hello.html
curl -s -o /dev/null http://localhost/nothing.html
curl -s -o /dev/null http://localhost/private/
curl -s -o /dev/null http://localhost/old.html
curl -s -o /dev/null -X POST http://localhost/
curl -s -o /dev/null -A "MyMonitor/1.0" http://localhost/
sudo tail -n 7 /var/log/apache2/access.log
```

`-A` sets the User-Agent: you will see it at the end of the last line.

## 08.3 · Every field of an access-log line

```text
127.0.0.1 - - [11/Nov/2026:10:15:32 +0530] "GET /hello.html HTTP/1.1" 200 21 "-" "curl/8.5.0"
│         │ │  │                           │                          │   │  │   │
1         2 3  4 + 5                       6 + 7 + 8                  9   10 11  12
```

| # | Field | Example | Means |
|---|---|---|---|
| 1 | client IP | `127.0.0.1` | who asked |
| 2 | ident | `-` | (unused) |
| 3 | user | `-` or `admin` | login name if basic auth was used |
| 4–5 | time | `[11/Nov/2026:10:15:32 +0530]` | when, with time zone |
| 6–8 | request | `"GET /hello.html HTTP/1.1"` | method, path, version |
| **9** | **status** | `200` | **how it went** |
| 10 | bytes | `21` | size of the body sent |
| 11 | referer | `"-"` | the page the link was on |
| 12 | user agent | `"curl/8.5.0"` | which program (spaces inside it shift later fields) |

```bash
grep -n "LogFormat" /etc/apache2/apache2.conf
```

```apache
LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined
```

| Code | Field |
|---|---|
| `%h` | client IP |
| `%u` | user |
| `%t` | time |
| `%r` | request line |
| `%>s` | final status |
| `%O` | bytes sent |
| `%D` / `%T` | time taken in µs / s (08.8) |

## 08.4 · An error-log line

```bash
sudo tail -n 5 /var/log/apache2/error.log
```

```text
[Wed Nov 11 10:16:02.123456 2026] [authz_core:error] [pid 1204:tid 1231] [client 127.0.0.1:50120] AH01630: client denied by server configuration: /var/www/html/private/
│                                  │          │       │                    │                        │
when                               module     level   process            who                      code + reason
```

The `AHnnnnn` code is searchable on the web. Match the two logs **by time**: a 403 in access.log at 10:16:02 has its reason in error.log at 10:16:02.

## 08.5 · Watch live while you test (two terminals)

Terminal 1:

```bash
sudo tail -F /var/log/apache2/access.log /var/log/apache2/error.log
```

Terminal 2:

```bash
curl -s -o /dev/null http://localhost/private/
curl -s -o /dev/null http://localhost/nothing.html
```

`tail -F` with two files prints `==> file <==` headers so you see which log each line came from. Stop with `Ctrl+C`.

## 08.6 · More detail in error.log: LogLevel

```
emerg  alert  crit  error  warn  notice  info  debug  trace1…trace8
←  only disasters                                        everything  →
```

Ubuntu default: `LogLevel warn`. Turn it up **for one module or one site** while you troubleshoot:

```apache
    LogLevel warn authz_core:debug
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -s -o /dev/null http://localhost/private/
sudo tail -n 5 /var/log/apache2/error.log
```

You now see each access decision. Set it back to `LogLevel warn` and reload. `debug` left on fills the disk.

## 08.7 · One-line answers to common questions

```bash
A=/var/log/apache2/access.log
```

| Question | Command |
|---|---|
| how many requests? | `sudo wc -l < $A` |
| how many 404s? | `sudo awk '$9 == 404' $A \| wc -l` |
| which pages gave 404? | `sudo awk '$9 == 404 {print $7}' $A \| sort \| uniq -c \| sort -rn` |
| status breakdown | `sudo cut -d' ' -f9 $A \| sort \| uniq -c \| sort -rn` |
| top client IPs | `sudo cut -d' ' -f1 $A \| sort \| uniq -c \| sort -rn \| head` |
| requests per minute | `sudo cut -d' ' -f4 $A \| cut -d: -f2,3 \| sort \| uniq -c` |
| all 5xx errors | `sudo awk '$9 >= 500' $A` |
| busiest URLs | `sudo awk '{print $7}' $A \| cut -d'?' -f1 \| sort \| uniq -c \| sort -rn \| head` |
| one client's requests | `sudo grep "^10.0.0.21 " $A` |

Run each. Use the **counting pipe** everywhere: `sort | uniq -c | sort -rn`.

## 08.8 · Log how long each request took

The default format has no timing. Add `%D` (microseconds) as the last field:

```bash
sudo vi /etc/apache2/sites-available/000-default.conf
```

```apache
    LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\" %D" timed
    CustomLog ${APACHE_LOG_DIR}/access.log timed
```

(Replace the existing `CustomLog … combined` line with the new one.)

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
for p in / /hello.html /shop/ /nothing.html; do curl -s -o /dev/null http://localhost$p; done
sudo tail -n 4 /var/log/apache2/access.log
sudo awk '{print $NF, $7}' /var/log/apache2/access.log | sort -n | tail -n 3
```

- `$NF` = the last field, whatever the user-agent did to the numbering.
- The biggest numbers are the slowest requests. Static files take well under 1000 µs (1 ms); a number like `2350417` would mean 2.35 s.
- Topic 13 adds a deliberately slow page so you can find a real slow request.

| Server | Field | Unit |
|---|---|---|
| Apache | `%D` | microseconds |
| Nginx | `$request_time` | seconds |
| IIS | `time-taken` | milliseconds |

## 08.9 · Old logs are rotated, not lost

```bash
ls -l /var/log/apache2/
cat /etc/logrotate.d/apache2
```

| Line | Means |
|---|---|
| `daily` | rotate once a day |
| `rotate 14` | keep 14 old files |
| `compress` / `delaycompress` | gzip old ones, keep yesterday's plain |
| `postrotate … reload` | Apache reopens its log files |

Force a rotation now to see it happen:

```bash
sudo logrotate -f /etc/logrotate.d/apache2
ls -l /var/log/apache2/
for p in / /nothing.html /hello.html; do curl -s -o /dev/null http://localhost$p; done
sudo logrotate -f /etc/logrotate.d/apache2
ls -l /var/log/apache2/
sudo zcat /var/log/apache2/access.log.2.gz | head -n 2
sudo zgrep -c " 404 " /var/log/apache2/access.log.*.gz
```

- First rotation: `access.log` → `access.log.1` and a new empty `access.log`.
- The curl lines put new lines into the empty file. Without them the second rotation does nothing: `notifempty` skips empty logs.
- Second rotation: `.1` → `.2.gz` (compressed), the new lines → `.1`.
- "It happened last Tuesday" → look in `.1` or `.N.gz`, not only in today's `access.log`.

---

## Exercises

1. Which user name appears in the access log for your successful `/admin/` login (topic 07)? Which field?
2. List every distinct status code in today's log with its count.
3. Which client IP sent the most requests? Which URL got the most 404s?
4. Show the 3 slowest requests with their paths and time in milliseconds.
5. After rotation, count the 404s in all old compressed logs together.

## Answers

1. `admin`, field 3: `sudo grep " /admin/ " /var/log/apache2/access.log | cut -d' ' -f3`.
2. `sudo cut -d' ' -f9 /var/log/apache2/access.log | sort | uniq -c | sort -rn`.
3. `sudo cut -d' ' -f1 … | sort | uniq -c | sort -rn | head -1`; `sudo awk '$9==404 {print $7}' … | sort | uniq -c | sort -rn | head -1`.
4. `sudo awk '{print $NF/1000, $7}' /var/log/apache2/access.log | sort -n | tail -n 3`.
5. `sudo zcat /var/log/apache2/access.log.*.gz | awk '$9 == 404' | wc -l`.
