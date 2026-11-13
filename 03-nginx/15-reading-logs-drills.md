# 15 · Reading logs: drills with known answers

**Time:** 45 min

**You will learn:** to read every field of an access-log line and an error-log line, match the two logs for one request, and answer real questions with `grep`, `cut`, `awk`, `sort` and `uniq`. You make a fixed set of traffic, so your answers must match the answer key exactly.

**Before you start:** topic 14.0 (the known-good `lab` site on 8083).

---

## 15.1 · Start clean and make known traffic

```bash
sudo cp /etc/nginx/lab.good /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
sudo truncate -s 0 /var/log/nginx/lab-access.log /var/log/nginx/lab-error.log
IP=$(hostname -I | awk '{print $1}')
U=http://lab.example.com:8083
for i in $(seq 1 20); do curl -s -o /dev/null $U/; done
for i in $(seq 1 5); do curl -s -o /dev/null -A "Mozilla/5.0 (Drill)" $U/docs/; done
for i in $(seq 1 3); do curl -s -o /dev/null $U/docs; done
for i in $(seq 1 4); do curl -s -o /dev/null $U/missing.html; done
for i in $(seq 1 2); do curl -s -o /dev/null $U/files/old.html; done
for i in $(seq 1 3); do curl -s -o /dev/null $U/secret/; done
for i in $(seq 1 2); do curl -s -o /dev/null $U/empty/; done
head -c 2000000 /dev/zero > ~/drill.bin
curl -s -o /dev/null -X POST --data-binary @$HOME/drill.bin $U/
rm ~/drill.bin
for i in $(seq 1 6); do curl -s -o /dev/null -H "Host: lab.example.com" http://$IP:8083/; done
curl -s -o /dev/null -e http://portal.example.com/ "$U/files/manual.html?lang=en"
echo "made 47 requests"
```

## 15.2 · Anatomy of an access-log line (timed format)

```bash
sudo tail -n 1 /var/log/nginx/lab-access.log
```

Sample line:

```text
127.0.0.1 - - [13/Nov/2026:01:30:12 +0000] "GET /files/manual.html?lang=en HTTP/1.1" 200 16 "http://portal.example.com/" "curl/8.5.0" rt=0.000 host=lab.example.com
```

| Field (`cut -d' ' -f`) | Value | Means |
|---|---|---|
| 1 | `127.0.0.1` | client address (`$remote_addr`) |
| 2 | `-` | not used (always `-`) |
| 3 | `-` | user name if Basic auth was used |
| 4–5 | `[13/Nov/2026:01:30:12 +0000]` | time and time zone of the **server** |
| 6–8 | `"GET /files/manual.html?lang=en HTTP/1.1"` | method, path **with** query, protocol |
| 9 | `200` | status |
| 10 | `16` | body bytes sent (headers not counted) |
| 11 | `"http://portal.example.com/"` | Referer: the page that linked here |
| 12+ | `"curl/8.5.0"` | User-Agent (may contain spaces: count fields from the left only up to 11) |
| end | `rt=0.000` `host=lab.example.com` | request time in seconds, Host header |

## 15.3 · Anatomy of an error-log line

```bash
sudo tail -n 3 /var/log/nginx/lab-error.log
```

Sample line:

```text
2026/11/13 01:30:11 [error] 8123#8123: *41 open() "/srv/labfiles/old.html" failed (2: No such file or directory), client: 127.0.0.1, server: lab.example.com, request: "GET /files/old.html HTTP/1.1", host: "lab.example.com:8083"
```

| Part | Value | Means |
|---|---|---|
| time | `2026/11/13 01:30:11` | server time, different layout from the access log |
| level | `[error]` | `emerg alert crit error warn notice info debug` |
| `pid#tid` | `8123#8123` | the worker that handled it |
| `*41` | connection number | the same number on several lines = the same visitor connection |
| message | `open() "/srv/labfiles/old.html" failed` | the real path on disk |
| errno | `(2: No such file or directory)` | the Linux reason |
| `client:` `server:` `request:` `host:` | | who, which server block, what, which Host |

## 15.4 · Match one request in both logs

```bash
sudo grep '" 413 ' /var/log/nginx/lab-access.log
sudo grep "too large body" /var/log/nginx/lab-error.log
```

- Same **time** (different layout), same **client**, same **request** line → the same request.
- The access log says **what** (`413`); the error log says **why** (`client intended to send too large body: 2000000 bytes`).
- Not every access-log error has an error-log line: a `404` from `try_files` and a `301` are written only to the access log.

---

## 15.5 · Drill questions

Answer each with one command. Write the command and the number.

1. How many requests are in `lab-access.log`?
2. Give the count for every status code.
3. Which two client addresses appear, and how many requests each?
4. Which paths returned 404? How many times each?
5. Which 404 paths also have an error-log line, and why not the others?
6. How many lines are in `lab-error.log`, and how many for each reason?
7. How many requests came from the "Drill" browser?
8. Which request had a Referer, and from which page?
9. Which requests got a 301, and where were they sent? (Use curl for the second part.)
10. How many bytes were sent in total for status 200?
11. Did any request take longer than 0.5 s?
12. For the 403 answers, split them by cause using only the error log.

## 15.6 · Answer key (commands and expected results)

```bash
L=/var/log/nginx/lab-access.log
E=/var/log/nginx/lab-error.log
sudo wc -l < $L
sudo cut -d' ' -f9 $L | sort | uniq -c | sort -rn
sudo cut -d' ' -f1 $L | sort | uniq -c | sort -rn
sudo awk '$9 == 404 {print $7}' $L | sort | uniq -c
sudo grep -o 'failed ([0-9]*: [^)]*)\|forbidden by rule\|directory index of "[^"]*" is forbidden\|too large body' $E | sort | uniq -c
sudo wc -l < $E
sudo grep -c "(Drill)" $L
sudo awk '$11 != "\"-\""' $L
sudo awk '$9 == 301 {print $7}' $L | sort | uniq -c
curl -sI http://lab.example.com:8083/docs | grep Location
sudo awk '$9 == 200 {sum += $10} END {print sum}' $L
sudo awk -F'rt=' '$2+0 > 0.5' $L | wc -l
```

| # | Expected |
|---|---|
| 1 | **47** |
| 2 | `32 200` · `6 404` · `5 403` · `3 301` · `1 413` |
| 3 | `127.0.0.1` **41**, your VM address (from `hostname -I`) **6** |
| 4 | `/missing.html` **4**, `/files/old.html` **2** |
| 5 | only `/files/old.html` (2 lines `failed (2: No such file or directory)`). `/missing.html` goes through `try_files … =404`, which writes no error-log line; `/files/` uses `alias` without try_files, so Nginx really opens the file and logs the failure |
| 6 | **8** lines: `2` × `failed (2: …)`, `3` × `forbidden by rule`, `2` × `directory index of "/var/www/lab/empty/" is forbidden`, `1` × `too large body` |
| 7 | **5** |
| 8 | `GET /files/manual.html?lang=en` from `http://portal.example.com/` |
| 9 | `/docs` × **3**, sent to `http://lab.example.com:8083/docs/` (add the slash for a folder) |
| 10 | 20 × 18 (`/`) + 5 × 20 (`/docs/`) + 6 × 18 (`/` via IP) + 1 × 16 (`manual.html`) = **584** |
| 11 | **0** |
| 12 | `/secret/` × 3 = `forbidden by rule` (allow/deny), `/empty/` × 2 = `directory index … is forbidden` (no index file) |

> If your numbers differ, first check `sudo wc -l` on both logs: an extra curl, or an old log not truncated, changes every count. Run 15.1 again from the start.

---

## 15.7 · Habits for reading any log

- Read the **newest** lines first (`tail -n 20`), then search back (`grep`), then count (`cut | sort | uniq -c | sort -rn`).
- Search **every** Nginx log when unsure: `sudo grep -rh "words" /var/log/nginx/`.
- Times: access log `[13/Nov/2026:01:30:12 +0000]`, error log `2026/11/13 01:30:11`. Same clock, different layout.
- One question at a time: **what** (access log status) → **why** (error log reason) → **where** (path, server block) → **since when** (first time it appears: `grep -m1`).
- Write down the one line that proved the cause. That line goes into the incident ticket.
