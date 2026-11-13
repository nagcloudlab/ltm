# 16 · Log-reading drills: one hour of PayBank traffic

**Time:** 60 min · **Work:** alone, then compare with a partner

**You will learn:** read an access log and an error log you did not write, field by field; answer the questions a manager asks during an incident ("since when?", "who?", "which page?", "how slow?"); and join the two logs by time.

All answers below were checked against the files the script creates. Your numbers must match exactly.

---

## 16.1 · Create the practice logs

Copy `make-apache-sample-logs.sh` to your VM (it is in this handout folder), then:

```bash
bash make-apache-sample-logs.sh
cd ~/lab/apache
ls -l
head -n 3 access.log
head -n 3 error.log
```

- One hour, 10:00–11:00 IST on 11 Nov 2026, of the PayBank portal.
- `access.log` uses the **combined** format plus `%D` (µs) as the last field (topic 08.8).
- The files are yours: no `sudo` needed.

## 16.2 · The access-log line, field by field

```bash
head -n 1 access.log
head -n 1 access.log | awk '{for (i = 1; i <= NF; i++) print i": "$i}'
```

Sample line:

```text
10.0.1.10 - - [11/Nov/2026:10:00:00 +0530] "GET / HTTP/1.1" 200 11022 "-" "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" 300
```

| awk field | Value | Means |
|---|---|---|
| `$1` | `10.0.1.10` | client IP |
| `$2` | `-` | ident (always `-`) |
| `$3` | `-` | user name after Basic auth, else `-` |
| `$4` `$5` | `[11/Nov/2026:10:00:00` `+0530]` | time and time zone |
| `$6` `$7` `$8` | `"GET` `/` `HTTP/1.1"` | method, path, protocol |
| `$9` | `200` | status |
| `$10` | `11022` | bytes sent |
| `$11` | `"-"` | referer |
| `$12` … | `"Mozilla/5.0` `(Windows` … | user agent: **several** fields, because it has spaces |
| `$NF` | `300` | time taken, µs (last field, always) |

- Fields up to `$11` are safe to count. After that, use `$NF` (last) or split on `"`.
- Split on the quote character to get the user agent in one piece:

```bash
head -n 1 access.log | awk -F'"' '{print "request: "$2; print "agent:   "$6}'
```

## 16.3 · The error-log line, piece by piece

```bash
grep AH01617 error.log | head -n 1
```

Sample line:

```text
[Wed Nov 11 10:20:00.101334 2026] [auth_basic:error] [pid 2411:tid 140322] [client 10.0.1.66:51230] AH01617: user admin: authentication failure for "/admin/": Password Mismatch
```

| Part | Value | Means |
|---|---|---|
| time | `Wed Nov 11 10:20:00.101334 2026` | to the microsecond, **different format** from the access log |
| module:level | `auth_basic:error` | the password module, level error |
| pid:tid | `2411:140322` | which worker process and thread |
| client | `10.0.1.66:51230` | client IP and its port |
| code | `AH01617` | fixed message number |
| text | `user admin … Password Mismatch` | the reason |

Count by module and level, and by code:

```bash
grep -o "\[[a-z_]*:[a-z]*\]" error.log | sort | uniq -c | sort -rn
grep -o "AH[0-9]*" error.log | sort | uniq -c | sort -rn
```

## 16.4 · Drill A: the big picture

```bash
wc -l < access.log
cut -d' ' -f9 access.log | sort | uniq -c | sort -rn
cut -d' ' -f4 access.log | cut -d: -f2,3 | cut -c1-4 | sort | uniq -c
```

- Line 3 counts requests per **10 minutes**: `10:3` = 10:30–10:39.

**Questions**

1. How many requests in the hour?
2. Which status codes appear, and how many of each?
3. Which 10-minute block was busiest?

## 16.5 · Drill B: errors and who caused them

```bash
awk '$9 == 404 {print $7}' access.log | sort | uniq -c | sort -rn | head -n 3
awk '$9 >= 500 {print $4, $1, $7, $9}' access.log
grep "core:alert" error.log | head -n 1
cut -d' ' -f1 access.log | sort | uniq -c | sort -rn | head -n 3
```

**Questions**

4. Which URL causes almost all 404s? Is it a real problem?
5. When did the 500 errors start and stop, which page, and what does error.log say the cause was?
6. Which IP sent the most requests? Is that suspicious?

## 16.6 · Drill C: a password attack and a scanner

```bash
grep " 401 " access.log | cut -d' ' -f1,3,4,7,9
grep -c AH01617 error.log
grep "^10.0.1.66 " access.log | cut -d' ' -f3,4,9
grep "^203.0.113.50 " access.log | cut -d' ' -f4,7,9
grep "203.0.113.50" error.log | grep -o "AH01630.*"
awk -F'"' '{print $6}' access.log | sort | uniq -c | sort -rn
```

**Questions**

7. Which IP guessed the admin password, how many failures, and did it get in?
8. Which IP is a scanner? List what it tried and what it got. Which tries did Apache block with a rule (error log)?
9. Which user agents appear, and how many requests each?

## 16.7 · Drill D: the slow period

```bash
awk '{print $NF, $4, $7}' access.log | sort -n | tail -n 3
awk '$NF > 1000000 {printf "%.1f s  %s %s\n", $NF/1000000, $4, $7}' access.log
awk '$7 ~ /transfer/ && $NF < 1000000 {s += $NF; n++} END {printf "normal transfer: %.0f ms average over %d requests\n", s/n/1000, n}' access.log
grep AH00484 error.log
```

**Questions**

10. What is the slowest request, and how long did it take in seconds?
11. Between which times were requests slower than 1 s, how many, and which pages?
12. How fast is `/cgi-bin/transfer.sh` normally?
13. What does error.log say at the same time, and how do the two logs together explain the incident?

## 16.8 · Drill E: join the two logs by time

The two logs write time differently:

| Log | Time looks like |
|---|---|
| access.log | `[11/Nov/2026:10:40:00 +0530]` |
| error.log | `[Wed Nov 11 10:40:00.310442 2026]` |

Search both for the same minute:

```bash
grep "11/Nov/2026:10:40" access.log | cut -d' ' -f1,4,7,9
grep "10:40:" error.log | cut -c1-140
```

**Questions**

14. For the 500 at 10:40:20, which client was it, and which error-log line belongs to it?
15. The 403 at 10:12:00: which page, which client, and which rule refused it?

---

## Answers

1. **262** requests.
2. `200` 197 · `404` 33 · `304` 15 · `500` 6 · `401` 6 · `403` 5.
3. `10:4` (10:40–10:49) with 55 requests: the 500s and the scanner were extra traffic on top of the normal 40 per 10 minutes.
4. `/favicon.ico` (30 of 33). The site has no favicon: harmless, but add one to make real 404s visible.
5. 10:40:00 to 10:40:50, six requests to `/blog/`, then `200` again at 10:41:30. error.log: `[core:alert] … /var/www/html/blog/.htaccess: Invalid command 'Redirekt'`: someone broke the `.htaccess`, then fixed it.
6. `10.0.1.21` with 10 requests, just above others with 9. Normal: no IP stands out (a single IP with hundreds would).
7. `10.0.1.66`, user `admin`: 5 failures (`401`) at 10:20:00–10:20:08, five `AH01617 … Password Mismatch` lines, then `200` at 10:20:12: it got in. Ask the owner of `admin` whether that was them.
8. `203.0.113.50` (an outside address, user agent `zgrab/0.x`) at 10:47:01–10:47:08 tried `/.env` 403, `/.git/config` 404, `/wp-login.php` 404, `/backup.zip` 403, `/server-status` 403, `/admin/` 401, `/phpmyadmin/` 404, `/config.php.bak` 403. The four 403s each have an `AH01630 client denied by server configuration` line: those were blocked by rules (hidden files, backups, status page).
9. `Mozilla/5.0 (Windows NT 10.0; Win64; x64)` 194 · `PayBank-Mobile/3.2` 60 · `zgrab/0.x` 8.
10. `POST /cgi-bin/transfer.sh` with `6700000` µs = **6.7 s**.
11. 10:30:45 to 10:34:45, **5** requests: 3 × `/cgi-bin/statement.sh`, 2 × `/cgi-bin/transfer.sh` (4.0–6.7 s each).
12. About **221 ms** average over 28 normal requests.
13. `AH00484: server reached MaxRequestWorkers setting` at 10:31:12. The application pages became 20–30 times slower from 10:30, held workers, and at 10:31 every worker was busy. Cause: the application or database behind `/cgi-bin/`, not Apache.
14. `10.0.1.22`; the error line `[Wed Nov 11 10:40:20.305500 2026] [core:alert] [pid 2410:tid 140314] [client 10.0.1.22:52026] /var/www/html/blog/.htaccess: Invalid command 'Redirekt' …` (same second, same client IP).
15. `/private/` from `10.0.1.40`; `AH01630: client denied by server configuration: /var/www/html/private/` (a `Require all denied` rule, topic 04).
