# 15 · Reading IIS logs: field by field, and drills

**Time:** 60 min · **Advanced**

**You will learn:**
- read any W3SVC line and any HTTPERR line without a table in front of you
- decide in which log a problem must appear
- put two logs side by side on one timeline
- answer the usual incident questions: since when, how many, who, which page, how slow

**Where:** 15.1–15.4 on Windows (your own logs); 15.5–15.8 on the **Ubuntu** VM with the practice logs from `make-iis-sample-log.sh` (topic 07).

---

## 15.1 · Which log? Follow the request

```
Client ──► HTTP.sys ──► (pool queue) ──► w3wp: modules, handler ──► response
            │                │                      │
            │ rejected here? │ pool down / full?    │ everything that got here
            ▼                ▼                      ▼
         HTTPERR          HTTPERR                W3SVC<ID>\u_ex*.log
       (NotFound, URL,  (Disabled, AppOffline,  (status.substatus win32 time-taken)
        Timer_*)         QueueFull)
            TLS failed? → System log, Schannel      pool crashed / recycled? → System log, WAS
                                                    app exception? → Application log, ASP.NET 1309
```

- **Rule 1:** `Server: Microsoft-IIS/10.0` in the response → the W3SVC log has the line.
- **Rule 2:** `Server: Microsoft-HTTPAPI/2.0` → only HTTPERR has it.
- **Rule 3:** no HTTP response at all (connection reset, TLS error) → event logs.

## 15.2 · Read one W3SVC line

Sample line:

```text
2026-11-11 05:01:15 10.0.0.5 POST /api/transfer - 80 - 10.20.1.45 PayBank-Mobile/3.2 - 500 0 0 7254 1420 30084
```

- `2026-11-11 05:01:15` → UTC; in India 10:31:15 IST.
- `10.0.0.5` → the server's own address (useful when several servers share one log store).
- `POST /api/transfer -` → method, path, no query string.
- `80` → plain http.
- `-` (user) → anonymous.
- `10.20.1.45` → the client (or the load balancer: topic 13.4).
- `PayBank-Mobile/3.2` → the mobile app, not a browser.
- `500 0 0` → status 500, sub-status 0 (the application failed), win32 0 (Windows had no problem).
- `7254 1420` → bytes sent (the error page) and received (the transfer request).
- `30084` → 30.1 seconds: the app waited 30 s and gave up → a **timeout** behind the app (database, another service).

Sample line:

```text
2026-11-11 04:45:03 10.0.0.5 POST /api/upload - 80 - 10.20.1.33 Mozilla/5.0+(Windows+NT+10.0;+Win64;+x64) http://portal.example.com/docs 413 1 0 5239 712 2
```

- `413 1` → Request Filtering refused a body over 30 MB (older IIS wrote `404 13`).
- `5239 712` → IIS sent a 5 KB error page and read only 712 bytes: the headers, not the file.
- `2` ms → refused at once, before any upload finished.
- Referer `…/docs` → the upload form is on the docs page.

## 15.3 · Read one HTTPERR line

```text
#Fields: date time c-ip c-port s-ip s-port cs-version cs-method cs-uri streamid streamid_ex sc-status s-siteid s-reason s-queuename transport
```

Sample line:

```text
2026-11-11 05:30:05 10.20.1.30 54000 10.0.0.5 80 HTTP/1.1 GET /api/accounts - - 503 2 AppOffline PortalPool TCP
```

- `c-ip c-port` → client address **and port** (HTTPERR keeps the port; W3SVC does not by default).
- `streamid streamid_ex` `- -` → only used for HTTP/2.
- `503` → what the client got.
- `2` → site ID 2 = Portal (`W3SVC2`).
- `AppOffline` → **the reason**: the pool was taken offline after errors (an admin stop would say `Disabled`).
- `PortalPool` → which pool (the queue name).

Sample line:

```text
2026-11-11 04:31:00 10.20.1.10 50100 10.0.0.5 80 - - - - - - - Timer_ConnectionIdle - TCP
```

- All dashes, reason `Timer_ConnectionIdle` → a keep-alive connection sat idle and HTTP.sys closed it. **Normal**; ignore.

| `s-reason` | Means | Worry? |
|---|---|---|
| `Timer_ConnectionIdle` | idle keep-alive connection closed | no |
| `Timer_MinBytesPerSecond` | client sent/received too slowly | only if many |
| `Connection_Dropped` / `Connection_Abandoned_By_ReqQueue` | connection lost; the second = the pool's worker died with requests waiting | yes if many: crash or recycle |
| `Disabled` | an admin stopped the pool | **yes**, if nobody planned it |
| `AppOffline` | pool stopped by Rapid-Fail after crashes | **yes** |
| `QueueFull` | pool's queue full | **yes**: back end too slow |
| `NotFound` | no binding for that Host (HTTP.sys answers 404; older Windows: `Hostname`, 400) | check bindings / DNS |
| `URL`, `FieldLength`, `Header`, `Verb` | malformed or too long request parts | usually scanners |

- The exact list of reasons depends slightly on the Windows version.

## 15.4 · On Windows: one-line answers

```powershell
$err = Get-ChildItem C:\Windows\System32\LogFiles\HTTPERR | Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $err.FullName | Where-Object { $_ -notlike "#*" } | ForEach-Object { ($_ -split " ")[13] } | Group-Object | Sort-Object Count -Descending | Select-Object Count, Name
Get-Content $err.FullName | Where-Object { $_ -notlike "#*" -and $_ -notmatch "Timer_ConnectionIdle" } | Select-Object -Last 10
```

- `[13]` = `s-reason` (field 14, counted from 0).
- The second line hides the harmless idle lines.

---

## 15.5 · Drills on Ubuntu: get the files

```bash
bash make-iis-sample-log.sh
cd ~/lab/iis
ls -l
head -5 httperr1.log
```

- `u_ex261111.log` = Portal's W3SVC log, 04:30–05:30 UTC.
- `httperr1.log` = HTTPERR for 04:30–05:33 UTC on the same server.
- W3SVC columns for `awk`: `$12` status · `$13` sub-status · `$14` win32 · `$15` sc-bytes · `$16` cs-bytes · `$17` **time-taken**.
- HTTPERR columns for `awk`: `$1` date · `$2` time · `$3` client · `$8` method · `$9` path · `$12` status · `$13` site ID · `$14` **reason** · `$15` queue · `$16` transport.

## 15.6 · Drills: W3SVC

**D1 · Busiest minute**

```bash
awk '!/^#/ {print substr($2,1,5)}' u_ex261111.log | sort | uniq -c | sort -rn | head -3
```

**D2 · Error rate per 10 minutes**

```bash
awk '!/^#/ {b=substr($2,1,4)"0"; n[b]++; if ($12>=400) e[b]++} END {for (b in n) printf "%s  %3d req  %3d errors  %5.1f%%\n", b, n[b], e[b], 100*e[b]/n[b]}' u_ex261111.log | sort
```

**D3 · Median and 95th percentile time for the API**

```bash
awk '!/^#/ && $5 ~ /^\/api\// {print $17}' u_ex261111.log | sort -n | awk '{v[NR]=$1} END {print "requests:", NR, " median:", v[int(NR*0.5)], " p95:", v[int(NR*0.95)], " max:", v[NR]}'
```

- **p95** = 95% of requests were faster than this. Averages hide slow requests; p95 shows them.

**D4 · "Successful" but slow**

```bash
awk '!/^#/ && $12==200 && $17>5000' u_ex261111.log | wc -l
```

**D5 · Which clients got server errors**

```bash
awk '!/^#/ && $12>=500 {print $9}' u_ex261111.log | sort | uniq -c | sort -rn
```

## 15.7 · Drills: HTTPERR

**H1 · Reasons**

```bash
awk '!/^#/ {print $14}' httperr1.log | sort | uniq -c | sort -rn
```

**H2 · The outage window in IST**

```bash
awk '!/^#/ && $14=="AppOffline" {print $1" "$2" UTC"}' httperr1.log | sed -n '1p;$p' | while read -r t; do TZ=Asia/Kolkata date -d "$t" '+%H:%M:%S IST'; done
```

**H3 · What happened just before the outage**

```bash
awk '!/^#/ && $2>="05:29:00" {print $2, $14, $9}' httperr1.log | head -5
```

**H4 · Who asked for a host name no site has**

```bash
awk '!/^#/ && $14=="NotFound" {print $2, $3, $8, $9, $12}' httperr1.log
```

## 15.8 · Drill: both logs on one timeline

```bash
{ awk '!/^#/ && $2>="04:58:00" && $2<"05:06:00" && ($17>5000 || $12>=500) {print $2, "W3SVC  ", $12"."$13, $5, $17"ms"}' u_ex261111.log; awk '!/^#/ && $2>="04:58:00" && $2<"05:06:00" && $14!="Timer_ConnectionIdle" {print $2, "HTTPERR", $12, $9, $14}' httperr1.log; } | sort
```

- Each log alone tells half the story. Sorted together by time, they show cause and effect.

---

## Questions

1. D1: which minute was busiest, and why is it not a real traffic peak?
2. D2: which 10-minute bucket had the worst error rate? Is that the incident?
3. D3: what are the median and p95 for `/api/`? What does the gap tell you?
4. D4: how many requests returned 200 but took more than 5 s?
5. H1: which reasons can you ignore, and which need action?
6. H2 + H3: when (IST) was Portal down, and what happened in the seconds before?
7. H4: who got `NotFound` from HTTP.sys and what were they probably doing?
8. 15.8: users said "some transfers failed with 503 around 10:30 IST", but the W3SVC log has no 503. Explain with the timeline.

## Answers

1. `05:12` with 16 requests: 12 of them are the scanner (`203.0.113.50`) in 12 seconds. Not real users.
2. `05:10` (30.8%), again because of the scanner's 404s. The real incident is in `04:50` and `05:00` (20% each), where the six 500s are; most other errors in every bucket are harmless `/favicon.ico` 404s. Error **rate** alone misleads: always look at which codes.
3. Median `180` ms, p95 `30070` ms (99 API requests). Most calls are fast, but 1 in 20 waits ~30 s: an incident, not general slowness.
4. `17`: users waited 5–9 s although the log says "200". Status codes alone hide slowness.
5. Ignore `Timer_ConnectionIdle` (20). Act on `AppOffline` (15), `QueueFull` (8), `Connection_Abandoned_By_ReqQueue` (3). `NotFound` (4): check, probably harmless.
6. `11:00:05`–`11:02:25` IST. Just before (05:29:58–05:30:00 UTC) three `Connection_Abandoned_By_ReqQueue` on `/api/transfer`: the worker process died with requests waiting, then the pool went offline (Rapid-Fail, topic 03.8). Next step: System log, WAS events 5009 / 5011 / 5002.
7. `198.51.100.7`, four `GET /` in 4 seconds, each answered `404` by HTTP.sys: someone browsing by IP address (no binding for it). Probably a scanner or a user with an old bookmark.
8. The 503s were sent by HTTP.sys (`QueueFull`, 04:59:05–05:05:30 UTC = 10:29–10:35 IST) while the pool's threads were stuck in 5–30 s API calls. They never reached IIS, so only HTTPERR has them. Root cause: the slow back end, not IIS.
