# 20 · Reading logs like an admin

**Time:** 45 min

**Practise on** your own lab VM and the PayBank lab server (`~/lab/srv`, fresh: `bash ~/01-linux/setup-lab.sh`).

**You will learn:** a fixed way to read any log line, the line formats of syslog, the journal, auth.log, the kernel, Apache and the PayBank app, how to put several logs on one timeline, and how to write your own test lines with `logger`. Then drills with answers.

---

## 20.1 · Five questions for every line

For any log line, find these five things before you think about the cause:

- **When?** date and time, and in which time zone
- **Where?** which server (host name)
- **Who?** which program (and its PID), which user or client IP
- **How bad?** the level: `INFO`, `WARN`, `ERROR`, `FATAL`, `err`, `crit`
- **What?** the message, and any code in it (`AH00957`, `(111)`, `Errno 24`, `status=203/EXEC`)

Then ask: **what happened just before?** (`grep -B 5`, Topic 09.9) and **did other logs say something at the same second?** (20.6).

## 20.2 · Where each kind of problem is written

| Problem | Read first |
|---|---|
| a service will not start / keeps restarting | `systemctl status NAME`, `journalctl -u NAME` |
| logins, sudo, ssh keys | `/var/log/auth.log` |
| everything else from the system | `/var/log/syslog` (or `journalctl`) |
| hardware, disk, OOM killer | `sudo dmesg -T`, `journalctl -k` |
| what was installed or upgraded | `/var/log/apt/history.log` |
| a web request | the web server's access log, then its error log |
| the application | its own log (`catalina.out`, `app.log`) |

## 20.3 · System log lines

Write two test lines yourself with `logger` (it writes to the system log, like an app would):

```bash
logger -t paybank -p user.err "payment-service health check FAILED (drill)"
logger -t paybank "nightly batch finished"
grep paybank /var/log/syslog | tail -n 2
journalctl -t paybank -n 2 --no-pager
journalctl -t paybank -p err --no-pager
```

Sample line from `/var/log/syslog`:

```text
2026-11-13T00:41:26.635532+00:00 lab-vm paybank: payment-service health check FAILED (drill)
```

- `2026-11-13T00:41:26.635532+00:00` = **when**: date `T` time, then the zone (`+00:00` = UTC, `+05:30` = IST)
- `lab-vm` = **where**
- `paybank:` = **who** (the tag you gave with `-t`)
- the rest = **what**

The same line in `journalctl`:

```text
Nov 13 00:41:26 lab-vm paybank[3323]: payment-service health check FAILED (drill)
```

- The journal adds the **PID** in `[ ]` and keeps the **priority**: `-p err` finds it, the "finished" line is not shown.
- `journalctl` shows lines in red/bold for `err` and worse when you look at it in a terminal.

## 20.4 · auth.log: who logged in, who used sudo

Make some entries, then read them:

```bash
sudo true
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new nosuchuser@localhost true
sudo grep -E "sudo:|sshd" /var/log/auth.log | tail -n 6
```

Sample lines:

```text
2026-11-13T00:41:25.505128+00:00 lab-vm sudo:  student : PWD=/home/student ; USER=root ; COMMAND=/usr/bin/true
2026-11-13T00:41:27.751237+00:00 lab-vm sshd[3333]: Invalid user nosuchuser from ::1 port 37372
2026-11-13T00:41:27.757417+00:00 lab-vm sshd[3333]: Connection closed by invalid user nosuchuser ::1 port 37372 [preauth]
```

| Part | Means |
|---|---|
| `sudo:  student :` | user `student` ran sudo |
| `PWD=/home/student` | from this folder |
| `USER=root` | as this user |
| `COMMAND=/usr/bin/true` | exactly this command (full path) |
| `Invalid user nosuchuser from ::1` | someone tried a user that does not exist, from that IP (`::1` = this machine) |
| `[preauth]` | the connection ended **before** login |

Other sshd lines you will meet:

| Line contains | Means |
|---|---|
| `Accepted publickey for student from 10.0.0.9` | key login OK |
| `Accepted password for student` | password login OK |
| `Failed password for student from 10.0.0.9` | wrong password, real user |
| `Failed password for invalid user admin` | guessing user names: often a scanner |
| `Authentication refused: bad ownership or modes for directory /home/student/.ssh` | key ignored because of permissions (Topic 21) |

Count failed logins per IP (a brute-force check):

```bash
sudo grep -E "Invalid user|Failed password" /var/log/auth.log | grep -oE "from [0-9a-f:.]+" | sort | uniq -c | sort -rn | head
```

## 20.5 · Kernel lines (dmesg)

```bash
sudo dmesg -T | tail -n 5
sudo dmesg -T --level=err,warn | tail -n 5
journalctl -k -p warning -b --no-pager | tail -n 5
```

Sample line:

```text
[Thu Nov 12 23:19:00 2026] Memory cgroup out of memory: Killed process 93243 (python3) total-vm:219196kB, anon-rss:51012kB …
```

- `-T` turns the kernel's "seconds since boot" into a real date.
- Words worth a `grep -i`: `killed process`, `out of memory`, `I/O error`, `EXT4-fs error`, `link is down`, `segfault`.

## 20.6 · One incident, three logs, one timeline

The PayBank incident at 09:13 left a trace in three different files with three different time formats:

```bash
cd ~/lab/srv
grep "09:13:1[45]" opt/tomcat/logs/catalina.out
grep "09:13:15" var/log/apache2/error.log
grep "09:13:15" var/log/apache2/access.log
```

| Log | Time format | Sample |
|---|---|---|
| app (`catalina.out`) | `2026-08-24 09:13:14` | `FATAL [main] Out of memory: Java heap space; JVM exiting` |
| Apache error log | `[Mon Aug 24 09:13:15.002210 2026]` | `(111)Connection refused: AH00957 … 127.0.0.1:8080 … failed` |
| Apache access log | `[24/Aug/2026:09:13:15 +0530]` | `"POST /payment/transfer HTTP/1.1" 503 45` |

Read them as a chain:

```
09:13:14  app       JVM out of memory, exits        (cause)
09:13:15  error.log Apache cannot connect to :8080  (because the app is gone)
09:13:15  access    users get 503                   (what customers see)
```

- **Rule:** the customer-facing log (access) shows the **symptom**; the earliest line in the **back-end** log is usually the **cause**.
- Before comparing times from different servers, check each server's time zone and clock (Topic 19.5).

### Anatomy of an Apache error-log line

```text
[Mon Aug 24 09:13:15.002210 2026] [proxy:error] [pid 1204:tid 1232] (111)Connection refused: AH00957: http: attempt to connect to 127.0.0.1:8080 (localhost:8080) failed
```

- `[proxy:error]` = module `proxy`, level `error`
- `[pid 1204:tid 1232]` = which Apache process
- `(111)Connection refused` = the Linux error number and its name: 111 = nobody listening
- `AH00957` = Apache's own message code: search it in the docs or the internet
- `127.0.0.1:8080` = the back end it tried

### Anatomy of the access-log line

See `00-setup.md`, "Log formats you will read": client IP, time, request, **status** (field 9), bytes, and **response time in µs** (last field).

---

## Drills

Do them on a fresh lab (`bash ~/01-linux/setup-lab.sh`) inside `~/lab/srv`.

1. What was the **first** problem of the day in `catalina.out`, and at what time?
2. How many minutes passed between the first `Slow query` and the first `FATAL`?
3. The access log has one `504`. How long did that request take, in seconds, and which **setting** in `app-prod.properties` explains the exact number?
4. At 09:11:45 a client got `401`. Which error-log line explains it, and what does it say?
5. At 09:14:41 a client got `403`. Which file did it ask for, and what does Apache's error log call the reason?
6. Which request took the longest of all, and what status did it get?
7. Write a `logger` line with tag `drill` and priority `warning`, then find it with `journalctl` using **only** the priority filter and the tag.
8. In `auth.log`, find the last `sudo` command **you** ran (not `grep` itself).
9. What did the app log say **one second before** Apache started getting `Connection refused`?

## Answers

- `grep -m1` = stop after the **first** match.

1. `grep -m1 -E "WARN|ERROR|FATAL" opt/tomcat/logs/catalina.out` → **09:02:30** `ERROR … NullPointerException at TransferServlet.java:88`.
2. First slow query 09:04:00, first FATAL 09:13:14 → about **9 minutes**: `grep -m1 "Slow query"` and `grep -m1 FATAL`.
3. `awk '$9 == 504 {print $4, $NF}' var/log/apache2/access.log` → `30001000` µs = **30.0 s**; `corebanking.timeoutMillis=30000` (30 s): the app waited for core-banking until its timeout.
4. `grep "09:11:45" var/log/apache2/error.log` → `[auth_basic:error] … AH01618: user admin not found: /admin/`: a login with a user name that does not exist.
5. `/.env`; `AH01630: client denied by server configuration`: an access rule blocked it (good).
6. `awk '{print $NF, $4, $6, $7, $9}' var/log/apache2/access.log | sort -n | tail -n 1` → `30001000 [24/Aug/2026:09:05:12 "POST /payment/transfer 504`: **504**, 30.0 s (`$NF` = the last field).
7. `logger -t drill -p user.warning "disk check drill"`; `journalctl -t drill -p warning --no-pager`.
8. `sudo grep "sudo:  $USER" /var/log/auth.log | grep -v grep | tail -n 1`.
9. `grep "09:13:14" opt/tomcat/logs/catalina.out` → pool exhausted, `Cannot get JDBC connection`, and `Out of memory: Java heap space; JVM exiting`.
