# 09 · Logs and grep

**Time:** 75 min

**Part A · Basics** on your own lab VM. **Part B · In depth** on the PayBank lab server (`~/lab/srv`, built by `00-setup.md`).

**You will learn in Part B:** context `-A -B -C`, `-E`, `-w`, `-o`, `-l`, patterns `^ $ [0-9]*`, `cut`, `awk`, `sort`, `uniq -c`, access-log analysis

---

# Part A · Basics

## 09.1 · Logs


| File | Contains |
|---|---|
| `/var/log/syslog` | general system messages |
| `/var/log/auth.log` | logins and sudo |
| `journalctl -u NAME` | one service's own log |

### Read a log line

```bash
sudo tail -n 3 /var/log/auth.log
```

```
2026-11-11T10:47:10.774310+05:30   lab-vm-01   sudo:   trainee01 … COMMAND=…
└──────────── WHEN ─────────────┘  └ WHERE ┘   └ WHO ┘ └──── WHAT ────┘
```

That line is a `sudo` command you ran earlier (Topic 05). Logs are evidence.

### Watch a log live

Open a **second** terminal and log in again (`ssh trainee01@10.0.0.5`).

Terminal 1:

```bash
sudo tail -f /var/log/auth.log
```

Terminal 2: `ssh trainee01@localhost`, type a **wrong** password once, then the right one, then `exit`.

Watch Terminal 1: you will see `Failed password for trainee01` and then `Accepted password for trainee01`. Stop with `Ctrl+C`.

### journalctl

```bash
journalctl -u cron -n 10
journalctl -u ssh --since "10 minutes ago"
journalctl -u cron -f          # follow live, Ctrl+C to stop
```


## 09.2 · grep: find the line you need


```bash
sudo grep Failed /var/log/auth.log
```

### Five options

| Command | Output | Meaning |
|---|---|---|
| `sudo grep -i failed /var/log/auth.log` | Failed… FAILED… | ignore capitals |
| `sudo grep -c Accepted /var/log/auth.log` | `4` | count matching lines |
| `grep -n Port /etc/ssh/sshd_config` | `23:#Port 22` (plus two comment lines that mention Port) | show line numbers |
| `grep -v "#" /etc/ssh/sshd_config` | lines without `#` | hide matches |
| `sudo grep -R PermitRootLogin /etc/ssh` | `/etc/ssh/sshd_config:#PermitRootLogin prohibit-password` | search a whole folder |

Join options like `ls`: `grep -in port /etc/ssh/sshd_config`

### grep on any output, with a pipe

```bash
ps -ef | grep cron
ls /etc | grep ssh
history | grep systemctl
```

### Answer 4 questions

| # | Question | Your answer |
|---|---|---|
| 1 | How many successful logins so far? | |
| 2 | On which line is `#Port 22`? | |
| 3 | Is cron running (which PID)? | |
| 4 | Which folders did you `cd` into today? | |


---

# Part B · In depth: the PayBank lab server

```bash
cd ~/lab/srv
```

## 09.3 · Shortcut names for this file

```bash
A=var/log/apache2/access.log
C=opt/tomcat/logs/catalina.out
```

`A=…` stores a path in a short name, a **variable**; `$A` uses it. No spaces around `=`. The names disappear when you log out: run these two lines again at the start of each session. Topic 12 covers variables fully.

## 09.4 · All the errors

```bash
grep ERROR $C
```

## 09.5 · How many? (`-c`)

```bash
grep -c ERROR $C
grep -c FATAL $C
grep -c WARN $C
```

`-c` counts **lines**, not words. A line with ERROR twice counts once.

## 09.6 · The root cause lives in FATAL

```bash
grep FATAL $C
```

Read them as a story:

```
09:13:14  DB pool full (20 of 20 busy, 31 waiting)
   └─► 09:13:14  JVM out of memory → payment-service dies
          └─► 09:14:30  auto-restart blocked by a lock file
```

## 09.7 · Capitals differ? (`-i`)

```bash
grep -c error $C
grep -ci error $C
```

Apps write `Error`, `ERROR`, `error`. When grep finds nothing, try `-i` before deciding it is not there.

## 09.8 · Where in the file? (`-n`)

```bash
grep -n FATAL $C
```

Now `vi +13 $C` opens the file directly at line 13.

## 09.9 · Context: what happened just before and after (`-B -A -C`) — the most useful option

```bash
grep -B 2 -A 1 "pool exhausted" $C
```

Two lines match ("pool exhausted" appears twice); their context overlaps, so grep prints one joined block. When matches are far apart, grep separates each block with a `--` line.

| Option | Shows |
|---|---|
| `-B 2` | 2 lines **B**efore each match |
| `-A 1` | 1 line **A**fter |
| `-C 3` | 3 lines on both sides (**C**ontext) |

The lines **before** a crash are often the real cause: here, slow queries were getting slower (2500 → 3200 → 4100 ms) before the pool filled up.

## 09.10 · Hide the noise (`-v`)

```bash
grep -v INFO $C | wc -l
grep -v '^#' ~/lab/srv/etc/payment/app-prod.properties | grep -v '^$'
```

Two pattern symbols you will see everywhere: `^` = start of the line, `$` = end of the line. The second line shows only real settings: no comment lines (`^#` = starts with #), no empty lines (`^$` = start then end).

## 09.11 · Several words at once (`-E`)

```bash
grep -E "ERROR|FATAL" $C | wc -l
grep -cE "Slow query|timed out" $C
```

`-E` turns on extended patterns; `|` means **or**. (`egrep` is the old name for `grep -E`.)

## 09.12 · Whole words only (`-w`)

```bash
grep -c 500 $A
grep -cw 500 $A
grep -cw 503 $A
```

## 09.13 · Pull out just the part you need (`-o`)

```bash
grep -o "query_time=[0-9]*ms" $C
grep -o "acct=[0-9]*" $A | sort | uniq -c | sort -rn
```

`[0-9]*` = any number of digits.

## 09.14 · Search every file in a folder (`-r`, `-l`)

```bash
grep -r "8080" etc/
grep -rl "maxTotal" etc/
```

`-l` prints only the **file names**: "which config files mention this?"

## 09.15 · cut: take one column

```bash
cut -d= -f1 etc/payment/app-prod.properties | grep -v '^#'    # keys
cut -d= -f2 etc/payment/app-prod.properties                   # values
cut -d' ' -f2 opt/tomcat/logs/catalina.out | head -3          # times
```

| Option | Means |
|---|---|
| `-d=` | split on `=` |
| `-d' '` | split on a single space |
| `-f2` | field 2; `-f1,3` fields 1 and 3; `-f2-` field 2 to the end |

### cut vs awk

The app log pads `INFO  ` with **two** spaces, so `cut -d' '` counts an empty field there and the columns shift:

```bash
cut -d' ' -f4 opt/tomcat/logs/catalina.out | head -2
awk '{print $4}' opt/tomcat/logs/catalina.out | head -2
```

> **Rule:** fixed single separator (`=`, `,`, `:`) → `cut`. Columns separated by any amount of spaces → `awk`.

## 09.16 · sort and uniq

```bash
awk '{print $2}' opt/tomcat/logs/catalina.out | cut -d: -f1,2 | sort | uniq -c
```

Events per minute: the busiest minutes are 09:00 (startup: 3 lines) and 09:13 (the crash: 3 lines). Quiet minutes in between are normal.

| Command | Does |
|---|---|
| `sort` | alphabetical |
| `sort -n` | numeric (2 before 10) |
| `sort -rn` | numeric, biggest first |
| `sort -k3` | by the 3rd column |
| `sort -t= -k2` | split on `=`, sort by field 2 |
| `sort -u` | sort and drop duplicates |
| `uniq -c` | count neighbouring duplicates |

## 09.17 · Pipes: build an answer step by step

**Question:** which component logged the most problems?

```bash
grep -E "ERROR|FATAL" $C                                   # 1 keep problem lines
grep -E "ERROR|FATAL" $C | awk '{print $4}'                 # 2 keep column 4
grep -E "ERROR|FATAL" $C | awk '{print $4}' | sort | uniq -c | sort -rn
```

| Step | Does |
|---|---|
| `awk '{print $4}'` | print the 4th space-separated field |
| `sort` | same values next to each other |
| `uniq -c` | count each group (needs `sort` first) |
| `sort -rn` | biggest number first (`-r` reverse, `-n` numeric) |

> Memorise **`sort | uniq -c | sort -rn`**. It answers "what is most common?" for any column of any log.

## 09.18 · Access-log analysis

### Count by status code

```bash
cut -d' ' -f9 $A | sort | uniq -c | sort -rn
```

### Who sends the most requests?

```bash
cut -d' ' -f1 $A | sort | uniq -c | sort -rn | head -3
```

### Which URLs are failing?

```bash
awk '$9 >= 500 {print $7}' $A | cut -d'?' -f1 | sort | uniq -c | sort -rn
```

`awk '$9 >= 500'` = keep lines whose 9th field (status) is 500 or more. `cut -d'?' -f1` drops the query string.

### When did the first 5xx happen?

```bash
awk '$9 >= 500 {print $4, $9; exit}' $A
```

### Someone scanning for weaknesses?

```bash
grep "10.0.0.203" $A
```

A bot probing for WordPress and secret files. Not the outage, but worth reporting.

---

## Exercises

1. Which file would show who ran `sudo` at 10:47?
2. `grep error /var/log/syslog` prints nothing, but you are sure there are errors. What do you try next?
3. How many lines in `catalina.out` are **not** INFO?
4. Show the 3 lines before the Out-of-memory line.
5. How many `NullPointerException` errors? Which source file and line?
6. List every distinct `query_time`, slowest last.
7. How many requests got `503`? From how many different IPs?
8. Which config file sets `jvm.heap.max`? Print the files only.
9. Count requests per HTTP method (GET, POST) in the access log.
10. Find the error.log line that explains the 09:13:15 `503`s.
11. List the keys that differ between prod and staging (keys only).
12. What is the production core-banking timeout in seconds?
13. Show all the requested paths from the access log, without query strings, each only once.
14. Which minute had the most access-log requests? (Hint: field 4, `cut -d: -f2,3`.)

## Answers

1. `/var/log/auth.log` (or `journalctl`), the line containing `sudo:` and `COMMAND=`.
2. Ignore capitals: `grep -i error /var/log/syslog`. Also check you have permission (`sudo`) and the right file.
3. `grep -vc INFO $C` → **13**.
4. `grep -B 3 "Out of memory" $C`.
5. `grep -c NullPointer $C` → **3**; `grep -o "TransferServlet.java:[0-9]*" $C | sort -u` → `TransferServlet.java:88`.
6. `grep -o "query_time=[0-9]*" $C | sort` → 2500, 3200, 4100.
7. `grep -cw 503 $A` → **9**; `grep -w 503 $A | cut -d' ' -f1 | sort -u | wc -l` → **6**.
8. `grep -rl "jvm.heap.max" etc/` → both properties files.
9. `cut -d'"' -f2 $A | cut -d' ' -f1 | sort | uniq -c` → GET 21, POST 9.
10. `grep "09:13:15" var/log/apache2/error.log` → `Connection refused: … connect to 127.0.0.1:8080 failed`: Apache could not reach the app server.
11. `diff etc/payment/app-prod.properties etc/payment/app-staging.properties | grep '^<' | cut -d' ' -f2 | cut -d= -f1` → the header comment, app.env, db.url, db.pool.maxTotal, corebanking.url, corebanking.timeoutMillis, jvm.heap.max, log.level.
12. `grep timeout etc/payment/app-prod.properties` → 30000 ms = **30 s**.
13. `awk '{print $7}' var/log/apache2/access.log | cut -d'?' -f1 | sort -u`.
14. `cut -d' ' -f4 var/log/apache2/access.log | cut -d: -f2,3 | sort | uniq -c | sort -rn | head -1` → **09:13** (5 requests).
