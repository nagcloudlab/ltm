# 07 · Analysing an IIS log on Linux

**Time:** 40 min

**You will learn:** reading a real IIS W3C log with `grep`, `awk`, `sort`, `uniq`; skipping `#` lines; counting status and sub-status codes; finding slow requests with `time-taken`; converting UTC to IST; and spotting an incident, a scanner and a misconfigured upload limit in one hour of traffic.

Admins often copy IIS logs to a Linux box (or open them in WSL) because the Linux text tools are fast. This topic runs on your **Ubuntu** VM.

---

## 07.1 · Create the practice log

- Copy `make-iis-sample-log.sh` from the Windows machine to the Ubuntu VM with `scp` (built into Windows), in PowerShell, in the folder that holds the file:

```powershell
scp make-iis-sample-log.sh student@[ubuntu-ip]:~
```

- Use your Ubuntu user name and address. Then on Ubuntu:

```bash
bash make-iis-sample-log.sh
cd ~/lab/iis
ls -l
head -6 u_ex261111.log
```

The file is one hour of traffic for the PayBank **Portal** site on 11 Nov 2026, in the default IIS format.

## 07.2 · Know your columns first

```bash
grep '^#Fields' u_ex261111.log | tr ' ' '\n' | cat -n
```

The `#Fields:` word is number 1, so subtract one: **the column numbers below are the ones `awk` uses**.

| awk | Field | | awk | Field |
|---|---|---|---|---|
| `$1` | date (UTC) | | `$9` | c-ip (client) |
| `$2` | time (UTC) | | `$10` | User-Agent |
| `$3` | s-ip | | `$11` | Referer |
| `$4` | method | | **`$12`** | **sc-status** |
| `$5` | URI stem (path) | | **`$13`** | **sc-substatus** |
| `$6` | query | | **`$14`** | **sc-win32-status** |
| `$7` | port | | `$15` | sc-bytes (sent) |
| `$8` | user name | | `$16` | cs-bytes (received) |
| | | | **`$17`** | **time-taken (ms)** |

> Apache's combined log puts the status in `$9`. In IIS it is `$12`. Always check the `#Fields:` line: an admin may have added or removed columns.

## 07.3 · Skip the `#` header lines

IIS writes header lines at the start of every file and again after every restart or change of fields:

```bash
grep -c '^#' u_ex261111.log
grep -vc '^#' u_ex261111.log
grep -v '^#' u_ex261111.log | head -3
```

Every command below either uses `grep -v '^#'` or the awk pattern `!/^#/`.

## 07.4 · Status codes, with sub-status

```bash
awk '!/^#/ {print $12}' u_ex261111.log | sort | uniq -c | sort -rn
awk '!/^#/ {print $12"."$13}' u_ex261111.log | sort | uniq -c | sort -rn
```

The second command is the IIS way: `404.0`, `404.7`, `404.8`, `401.1`, `401.2` are **different problems** that all look like plain 404 or 401 to the visitor.

| Seen | Means | Who acts |
|---|---|---|
| `404.0` | file not found | content team / ignore favicon |
| `413.1` | upload bigger than `maxAllowedContentLength` (older IIS: `404.13`) | IIS admin |
| `404.7` / `404.8` | blocked extension / hidden segment | nobody: filtering works |
| `401.2` then `401.1` | no login, then wrong password | user / helpdesk |
| `500.0` | the application failed | developers |

## 07.5 · Which pages fail?

```bash
awk '!/^#/ && $12==404 {print $5}' u_ex261111.log | sort | uniq -c | sort -rn | head
awk '!/^#/ && $12>=500 {print $2, $4, $5, $12"."$13, $17"ms"}' u_ex261111.log
```

## 07.6 · Slow requests with time-taken

```bash
awk '!/^#/' u_ex261111.log | sort -k17,17n | tail -5
awk '!/^#/ && $17>5000 {print $2, $5, $17}' u_ex261111.log
awk '!/^#/ && $17>5000 {print $5}' u_ex261111.log | sort | uniq -c | sort -rn
```

Average time per URL:

```bash
awk '!/^#/ {sum[$5]+=$17; n[$5]++} END {for (u in sum) printf "%8.0f ms  %4d req  %s\n", sum[u]/n[u], n[u], u}' u_ex261111.log | sort -rn
```

`time-taken` is in **milliseconds** (Apache `%D` is microseconds; Nginx `$request_time` is seconds).

## 07.7 · Requests per 10 minutes: see the incident shape

```bash
awk '!/^#/ {print substr($2,1,4)"0"}' u_ex261111.log | sort | uniq -c
awk '!/^#/ && $12>=500 {print substr($2,1,4)"0"}' u_ex261111.log | sort | uniq -c
awk '!/^#/ && $17>5000 {print substr($2,1,4)"0"}' u_ex261111.log | sort | uniq -c
```

`substr($2,1,4)` keeps `04:5` from `04:56:15`; adding `"0"` gives the 10-minute bucket `04:50`.

## 07.8 · UTC to IST

IIS times are **UTC**. Users in India report times in **IST = UTC + 5:30**.

```bash
TZ=Asia/Kolkata date -d '2026-11-11 04:56:15 UTC'
TZ=UTC date -d 'TZ="Asia/Kolkata" 2026-11-11 10:30'
```

Convert every line on the fly:

```bash
awk '!/^#/ && $12>=500 {print $1" "$2" UTC"}' u_ex261111.log | while read -r t; do TZ=Asia/Kolkata date -d "$t" '+%H:%M:%S IST'; done
```

> "Users say it was slow at 10:30" → search the log around **05:00**.

## 07.9 · Who is calling? Clients, agents, users

```bash
awk '!/^#/ {print $9}' u_ex261111.log | sort | uniq -c | sort -rn | head -5
awk '!/^#/ {print $10}' u_ex261111.log | sort | uniq -c | sort -rn
awk '!/^#/ && $8!="-" {print $2, $8, $5, $12}' u_ex261111.log
awk '!/^#/ && $9=="203.0.113.50" {print $2, $5, $12"."$13}' u_ex261111.log
```

| Clue | Means |
|---|---|
| one outside IP, many different paths, all 404, in seconds | a **scanner** looking for weak spots |
| `+` in User-Agent | IIS writes spaces as `+` |
| `$8` filled in | the user logged in (Basic/Windows authentication) |

## 07.10 · The win32-status column

```bash
awk '!/^#/ && $14!=0 {print $12"."$13, "win32="$14}' u_ex261111.log | sort | uniq -c | sort -rn
```

| win32 | Windows meaning |
|---|---|
| 0 | success |
| 2 | file not found |
| 3 | path (folder) not found |
| 5 | access denied |
| 64 | the client closed the connection |
| 1326 | logon failure: wrong user name or password |
| 121 | semaphore timeout (slow network to client) |

---

## Exercises

Use only `~/lab/iis/u_ex261111.log`.

1. How many requests are in the log (not counting `#` lines)?
2. Which status.substatus is the most common error, and which URL causes almost all of it?
3. How many 500 errors are there? Give the first and the last in **IST**.
4. What was the slowest request (path and time-taken in seconds)?
5. In which 10-minute bucket (UTC) did the 500 errors start? What was happening to `/api/accounts` and `/api/balance` at the same time?
6. One client was uploading a file that IIS refused. Which IP, which sub-status, and what setting fixes it?
7. Which IP is a scanner? How many requests did it send, and how many did Request Filtering block (sub-status 7 or 8)?
8. Someone tried `/reports/`. What happened in order, and who logged in at the end?
9. What is the average time-taken of **successful** `POST /api/transfer` requests?

## Answers

1. `grep -vc '^#' u_ex261111.log` → **260**.
2. `404.0` (32), of which `/favicon.ico` is 24: the site has no favicon. Harmless, but noisy.
3. 6. `awk '!/^#/ && $12==500 {print $2}'` → first 04:56:15 UTC = **10:26:15 IST**, last 05:08:45 UTC = **10:38:45 IST**.
4. `POST /api/transfer` at 05:08:45 UTC, **30105 ms = 30.1 s** (a timeout: about 30 s every time).
5. `04:50` (2 errors), then `05:00` (4). From 04:55:45 to 05:09:30 UTC, 23 requests took over 5 s: 11 `/api/accounts`, 6 `/api/balance`, 6 `/api/transfer`. Every API was slow, not just transfer: look at the shared back end (the database), not one page.
6. `10.20.1.33`, three times `413.1` at 04:45 UTC (`cs-bytes` only 712: the body was refused). Raise `maxAllowedContentLength` (topic 05.5) for that site, if the business agrees.
7. `203.0.113.50`, 12 requests between 05:12:01 and 05:12:12 UTC; 4 blocked by Request Filtering (`/web.config` and `/bin/app.dll` → 404.8, `/backup.bak` and `/db.mdb` → 404.7). The other 8 were plain 404 (files do not exist).
8. 04:55:01 `401.2` (no credentials), 04:55:09 and 04:55:17 `401.1` with win32 1326 (wrong password), then 04:55:30 `200` as `webadmin`, who also opened `/reports/nov.pdf`.
9. `awk '!/^#/ && $5=="/api/transfer" && $12==200 {s+=$17; n++} END {print s/n, n}'` → **600 ms** over 18 requests (compare 30 s for the failing ones).
