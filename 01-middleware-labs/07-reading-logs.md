# Lab 6 — reading Apache, Nginx, Tomcat, Kong and IIS logs

- **Needs:** [Lab 5](05-api-gateway.md) completed; all services running
- **You build:** the skill to read every log line the payment stack writes, follow one request across logs, convert IST ↔ UTC, and analyse a Windows IIS log on Linux

- Goal: say *which component* produced an error before saying *who* must fix it.
- **Part A** — your live stack from Labs 1–5.
- **Part B** — prepared sample logs in `~/ltm/middleware-labs/project-files/samples/` (fixed answers).
- **Part C** — a Microsoft IIS log, read on Linux (no Windows needed).

## 1. Where every log lives

| Component | Log | What it records |
| --- | --- | --- |
| Apache | `/var/log/apache2/payment-access.log` | One line per request |
| Apache | `/var/log/apache2/payment-error.log` | Problems: denied access, failed logins, backend errors |
| Nginx | `/var/log/nginx/payment-access.log` | One line per request |
| Nginx | `/var/log/nginx/payment-error.log` | Problems, including upstream (Tomcat) errors |
| Tomcat | `sudo journalctl -u tomcat` | Console output: startup, deployment, shutdown, startup failures |
| Tomcat | `/opt/tomcat/logs/catalina.YYYY-MM-DD.log` | The same server messages, in a file |
| Tomcat | `/opt/tomcat/logs/localhost.YYYY-MM-DD.log` | Application exceptions and stack traces |
| Tomcat | `/opt/tomcat/logs/localhost_access_log.YYYY-MM-DD.txt` | One line per request that reached Tomcat |
| Kong | `/var/log/kong-lab/access.log` | One line per gateway request, with a request ID |
| Kong | `/var/log/kong-lab/error.log` | Upstream errors and gateway messages |
| Any service | `sudo journalctl -u <unit>` | Start, stop and failure messages from systemd |
| IIS (Windows) | `C:\inetpub\logs\LogFiles\W3SVC<site-id>\u_exYYMMDD.log` | One line per request (W3C format) |

List the web and gateway log folders:

```bash
sudo ls -l /var/log/apache2/ /var/log/nginx/ /var/log/kong-lab/
```

List the Tomcat log folder:

```bash
sudo ls -l /opt/tomcat/logs/
```

- Logs belong to root or a service account: read them with `sudo`.
- A `*` inside `/opt/tomcat/logs` needs `sudo sh -c '...'` — your shell cannot list that folder, so it cannot expand the `*`.

## 2. Time zones before anything else

- Two logs can show the same moment with different clock values. Check your laptop first.

Show the time zone settings:

```bash
timedatectl
```

Local time:

```bash
date
```

UTC time:

```bash
date -u
```

- IST = UTC **+5:30**, no daylight saving.
- Apache, Nginx, Tomcat, Kong **access** logs: local time **with** offset, e.g. `[11/Nov/2026:10:42:25 +0530]`.
- Nginx and Kong **error** logs: local time **without** offset, e.g. `2026/11/11 10:42:25`.
- `journalctl`: laptop's time zone; add `--utc` for UTC.
- IIS W3C logs: always **UTC**.

Convert UTC → IST:

```bash
TZ=Asia/Kolkata date -d '2026-11-11 05:12:25 UTC'
```

Convert IST → UTC:

```bash
date -u -d 'TZ="Asia/Kolkata" 2026-11-11 10:42:25'
```

Journal in local time:

```bash
sudo journalctl -u tomcat -n 3 --no-pager
```

Journal in UTC:

```bash
sudo journalctl -u tomcat -n 3 --no-pager --utc
```

- Sample output (the two conversions):

```text
Wed Nov 11 10:42:25 IST 2026
Wed Nov 11 05:12:25 UTC 2026
```

- Always write the zone in incident notes: "10:42 IST", not "10:42".

---

# Part A — your live logs

## 3. Make fresh, traceable traffic

- Each request carries a unique `?trace=` marker, so you can find it in every log.
- If you did the optional lockdown at the end of Lab 5, restore the proxy routes first.

Restore the Apache proxy site:

```bash
sudo cp ~/ltm/middleware-labs/project-files/config/apache-proxy.conf /etc/apache2/sites-available/payment-portal.conf
```

Restore the Nginx proxy site:

```bash
sudo cp ~/ltm/middleware-labs/project-files/config/nginx-proxy.conf /etc/nginx/sites-available/payment-portal
```

Test and reload Apache:

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
```

Test and reload Nginx:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Now generate traffic. Via Apache (expect `200`):

```bash
curl -s -o /dev/null -w '%{http_code}\n' 'http://portal.example.test/payment/status?trace=lab6-apache'
```

Via Nginx (expect `200`):

```bash
curl -s -o /dev/null -w '%{http_code}\n' 'http://portal.example.test:8081/payment/status?trace=lab6-nginx'
```

Application failure (expect `500`):

```bash
curl -s -o /dev/null -w '%{http_code}\n' 'http://portal.example.test/payment/fail?trace=lab6-fail'
```

Denied path (expect `403`):

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://portal.example.test/private/
```

Wrong password (expect `401`):

```bash
curl -s -o /dev/null -w '%{http_code}\n' -u admin:wrong-password http://portal.example.test/admin/
```

Conditional request (expect `304`):

```bash
curl -s -o /dev/null -w '%{http_code}\n' -z /var/www/payment-portal/style.css http://portal.example.test/style.css
```

Kong without a key (expect `401`):

```bash
curl -s -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:8000/api/payment/status?trace=lab6-nokey'
```

Kong with a key (expect a full `200` response with headers):

```bash
curl -s -i -H 'apikey: demo-key-123' 'http://127.0.0.1:8000/api/payment/status?trace=lab6-kong'
```

- **Expected, in order:** `200`, `200`, `500`, `403`, `401`, `304`, `401`, full `200`.
- **If the last one is `429`:** the Lab 5 quota counter is full — wait for the next minute and repeat only that line.
- `-z <file>` = "only if changed since this file's date"; unchanged → `304 Not Modified`, no body.
- Note the `X-Kong-Request-Id:` header in the last response — used in step 8.

## 4. Apache access log, field by field

Show the last 8 requests:

```bash
sudo tail -n 8 /var/log/apache2/payment-access.log
```

- Sample line:

```text
127.0.0.1 - - [15/Nov/2026:12:27:26 +0530] "GET /payment/fail?trace=fail-web-1 HTTP/1.1" 500 1467 "-" "curl/8.5.0"
```

- **combined** format (`CustomLog ... combined` in the site file); awk splits on spaces:

| awk field | Value in the sample | Meaning |
| --- | --- | --- |
| `$1` | `127.0.0.1` | Client address that connected to Apache |
| `$2` | `-` | Old "identd" field, nearly always `-` |
| `$3` | `-` | Authenticated user name, or `-` |
| `$4` `$5` | `[15/Nov/2026:12:27:26 +0530]` | Time and offset |
| `$6` | `"GET` | Method |
| `$7` | `/payment/fail?trace=fail-web-1` | Path and query |
| `$8` | `HTTP/1.1"` | Protocol |
| `$9` | `500` | Status code sent to the client |
| `$10` | `1467` | Response size in bytes |
| `$11` | `"-"` | Referer (page that linked here) |
| `$12` onward | `"curl/8.5.0"` | User agent; a browser's spans many fields |

- Apache logs when the request **arrived**; Nginx, Tomcat and Kong log when it **finished**. For slow requests the times differ by the duration.
- A failed login still shows the user in `$3`: `127.0.0.1 - admin [...] "GET /admin/ HTTP/1.1" 401 ...`.

Count requests per status code:

```bash
sudo awk '{print $9}' /var/log/apache2/payment-access.log | sort | uniq -c | sort -rn
```

List recent errors (time, path, status):

```bash
sudo awk '$9 >= 400 {print $4, $7, $9}' /var/log/apache2/payment-access.log | tail -n 10
```

List requests with a user name:

```bash
sudo awk '$3 != "-" {print $3, $7, $9}' /var/log/apache2/payment-access.log | tail -n 5
```

## 5. Apache error log, field by field

Show the last 6 errors:

```bash
sudo tail -n 6 /var/log/apache2/payment-error.log
```

- Sample line:

```text
[Sun Nov 15 12:27:23.126090 2026] [auth_basic:error] [pid 5596:tid 281472978514208] [client 127.0.0.1:55200] AH01617: user admin: authentication failure for "/admin/": Password Mismatch
```

| Part | Meaning |
| --- | --- |
| `[Sun Nov 15 12:27:23.126090 2026]` | Local time, with microseconds |
| `[auth_basic:error]` | Module that wrote it, and level |
| `[pid ...:tid ...]` | Apache worker process and thread |
| `[client 127.0.0.1:55200]` | Client address and port |
| `AH01617:` | Apache message number: search it in the Apache documentation |
| rest | Plain explanation |

Messages you caused in Labs 1–4:

| Message | Meaning |
| --- | --- |
| `AH01630: client denied by server configuration` | A `Require` rule blocked the path (403) |
| `AH01617: ... Password Mismatch` | Wrong password (401) |
| `(13)Permission denied: ... AH00035: access to /index.html denied (filesystem path ...)` | Filesystem permissions (403) |
| `(111)Connection refused: AH00957: ... attempt to connect to 127.0.0.1:8080 ... failed` | Backend not listening (503) |
| `(70007)The timeout specified has expired: ... AH01102: error reading status line from remote server` | Backend too slow (502) |

- A 500 produced by Tomcat appears only in Apache's **access** log; the error log stays silent (Apache just forwarded the answer).

## 6. Nginx access and error logs

- Same combined format, so the same awk fields work.

Show the last 5 requests:

```bash
sudo tail -n 5 /var/log/nginx/payment-access.log
```

Count requests per status code:

```bash
sudo awk '{print $9}' /var/log/nginx/payment-access.log | sort | uniq -c | sort -rn
```

Show the last 5 errors:

```bash
sudo tail -n 5 /var/log/nginx/payment-error.log
```

- Sample line:

```text
2026/11/15 12:27:41 [error] 5582#5582: *17 connect() failed (111: Connection refused) while connecting to upstream, client: 127.0.0.1, server: portal.example.test, request: "GET /payment/status?trace=down-ngx-1 HTTP/1.1", upstream: "http://127.0.0.1:8080/payment/status?trace=down-ngx-1", host: "portal.example.test:8081"
```

| Part | Meaning |
| --- | --- |
| `2026/11/15 12:27:41` | Local time, no offset |
| `[error]` | Level: `emerg`, `crit`, `error`, `warn`, `notice` |
| `5582#5582:` | Worker process ID and thread |
| `*17` | Connection number: the same number links several lines of one connection |
| message | What went wrong |
| `client:`, `server:`, `request:` | Who asked, which `server_name`, which request |
| `upstream:` | The exact backend URL Nginx tried |
| `host:` | Host header the client sent |

| Error log message | Code to client |
| --- | --- |
| `connect() failed (111: Connection refused) while connecting to upstream` | 502 |
| `upstream timed out (110: Connection timed out) while reading response header from upstream` | 504 |
| `access forbidden by rule` | 403 |
| `user "admin": password mismatch` | 401 |
| `open() "..." failed (13: Permission denied)` | 403 or 500 |

## 7. Tomcat: four places to look

### Startup and shutdown: the journal

Last 25 journal lines:

```bash
sudo journalctl -u tomcat -n 25 --no-pager
```

Only startup, deployment and severe lines:

```bash
sudo journalctl -u tomcat --no-pager | grep -E 'Server startup in|Deployment of web application archive|SEVERE'
```

- Sample lines:

```text
Nov 15 12:27:46 lab-laptop catalina.sh[5893]: 15-Nov-2026 12:27:46.487 INFO [main] org.apache.catalina.startup.HostConfig.deployWAR Deployment of web application archive [/opt/tomcat/webapps/payment.war] has finished in [290] ms
Nov 15 12:27:46 lab-laptop catalina.sh[5893]: 15-Nov-2026 12:27:46.703 INFO [main] org.apache.catalina.startup.Catalina.start Server startup in [550] milliseconds
```

- Journal prefix (`Nov 15 12:27:46 lab-laptop catalina.sh[5893]:`): time, host, program, PID.
- Then Tomcat's line: date, time, **level** (`INFO`, `WARNING`, `SEVERE`), thread `[...]`, Java class, message.
- No `Server startup in [...] milliseconds` after a restart = Tomcat did not start: read the `SEVERE` lines above.

| Cause | Line in the journal |
| --- | --- |
| Broken `server.xml` | `SAXParseException; systemId: file:/opt/tomcat/conf/server.xml; lineNumber: ...` |
| Wrong `JAVA_HOME` in the unit | `The JAVA_HOME environment variable is not defined correctly` |
| Unreadable configuration | `java.io.FileNotFoundException: /opt/tomcat/conf/server.xml (Permission denied)` |
| Port already used | `java.net.BindException: Address already in use` |

- `catalina.YYYY-MM-DD.log` = same messages as a file; useful when the journal has rotated.

Tail the catalina log:

```bash
sudo sh -c 'tail -n 5 /opt/tomcat/logs/catalina.*.log'
```

### Application errors: `localhost.YYYY-MM-DD.log`

Count exceptions:

```bash
sudo sh -c 'grep -c SEVERE /opt/tomcat/logs/localhost.*.log'
```

Show the latest stack trace:

```bash
sudo sh -c 'grep -A6 "SEVERE" /opt/tomcat/logs/localhost.*.log | tail -n 8'
```

- Sample lines:

```text
15-Nov-2026 12:27:26.155 SEVERE [http-nio-127.0.0.1-8080-exec-6] org.apache.catalina.core.StandardWrapperValve.invoke Servlet.service() for servlet [Payment] in context with path [/payment] threw exception [LAB simulated payment failure; hand stack trace to developers] with root cause
	jakarta.servlet.ServletException: LAB simulated payment failure; hand stack trace to developers
		at lab.PaymentServlet.doGet(PaymentServlet.java:15)
		at jakarta.servlet.http.HttpServlet.service(HttpServlet.java:564)
```

- `SEVERE` line: servlet and context (`/payment`).
- Next line: **exception type and message** — the most important line.
- `at ...` lines: method calls, newest first. First `at` in the app's own package (`lab.PaymentServlet ... line 15`) = where developers look. `org.apache.catalina` / `jakarta.servlet` = Tomcat itself.
- Give developers: time with zone, URL, exception line, first application `at` line.

### Requests: `localhost_access_log.YYYY-MM-DD.txt`

Tail Tomcat's access log:

```bash
sudo sh -c 'tail -n 5 /opt/tomcat/logs/localhost_access_log.*.txt'
```

- Sample line:

```text
127.0.0.1 - - [15/Nov/2026:12:27:26 +0530] "GET /payment/fail?trace=fail-web-1 HTTP/1.1" 500 1230
```

- **common** format: fields `$1`–`$10`, no referer/user agent. Status is still `$9`.
- Client is always `127.0.0.1`: Tomcat sees the proxy or gateway, not the user.
- Nginx forwards as `HTTP/1.0`; Apache and Kong send `HTTP/1.1` — a quick way to tell the frontend.
- Written in batches: wait 10 seconds before deciding a request "never arrived".

## 8. Kong access and error logs

Tail Kong's access log:

```bash
sudo tail -n 5 /var/log/kong-lab/access.log
```

- Sample line:

```text
127.0.0.1 - - [15/Nov/2026:12:27:41 +0530] "GET /api/payment/status?trace=down-api-1 HTTP/1.1" 502 126 "-" "curl/8.5.0" kong_request_id: "b2a8762e31efd922a551d52f4fe9b916"
```

- Combined format plus `kong_request_id`. Path is the **public** one (`/api/payment/...`); Tomcat logs the backend path (`/payment/...`).
- 401 (no/wrong key), 403 (ACL), 429 (quota) are decided by Kong: only in Kong's access log; Tomcat never sees them; error log quiet.
- The same ID is in the error log and in the `X-Kong-Request-Id` response header.

Find the step 3 request:

```bash
sudo grep 'lab6-kong' /var/log/kong-lab/access.log
```

Print only its request ID:

```bash
sudo awk '/lab6-kong/ {print $NF}' /var/log/kong-lab/access.log
```

Tail Kong's error log:

```bash
sudo tail -n 3 /var/log/kong-lab/error.log
```

- Sample error line:

```text
2026/11/15 12:27:41 [error] 5732#0: *658 connect() failed (111: Connection refused) while connecting to upstream, client: 127.0.0.1, server: kong, request: "GET /api/payment/status?trace=down-api-1 HTTP/1.1", upstream: "http://127.0.0.1:8080/payment/status?trace=down-api-1", host: "127.0.0.1:8000", request_id: "b2a8762e31efd922a551d52f4fe9b916"
```

- Kong is built on Nginx: error lines read like Nginx's, plus `request_id`.
- A user can quote their `X-Kong-Request-Id`; grep for it in both Kong logs.

## 9. Follow one request across hops

- Tomcat writes its access log in batches, so wait first.

Wait 10 seconds:

```bash
sleep 10
```

`lab6-apache` at Apache:

```bash
sudo grep -h 'lab6-apache' /var/log/apache2/payment-access.log
```

`lab6-apache` at Tomcat:

```bash
sudo sh -c 'grep -h "lab6-apache" /opt/tomcat/logs/localhost_access_log.*.txt'
```

`lab6-kong` at Kong:

```bash
sudo grep -h 'lab6-kong' /var/log/kong-lab/access.log
```

`lab6-kong` at Tomcat:

```bash
sudo sh -c 'grep -h "lab6-kong" /opt/tomcat/logs/localhost_access_log.*.txt'
```

`lab6-nokey` at Kong:

```bash
sudo grep -h 'lab6-nokey' /var/log/kong-lab/access.log
```

`lab6-nokey` at Tomcat:

```bash
sudo sh -c 'grep -h "lab6-nokey" /opt/tomcat/logs/localhost_access_log.*.txt' || echo "not in Tomcat: Kong rejected it"
```

For each request, write down:

- the frontend and backend lines, with time and status;
- **same** status at both hops (backend produced it) or **different** (frontend produced it);
- for `lab6-nokey`, why there is no backend line.

---

# Part B — prepared sample logs (fixed answers)

- Captured from this stack during one short incident, 15 Nov 2026, 12:27–12:28 IST: normal traffic, three application failures, two rejected API calls, one slow request, a Tomcat stop and start.

Go to the samples:

```bash
cd ~/ltm/middleware-labs/project-files/samples
```

List them:

```bash
ls -R
```

## 10. Sample exercises

- Work out each answer with commands, then check the [answers](#answers) at the end.

**1. Status counts in `apache/payment-access.txt`.**

```bash
awk '{print $9}' apache/payment-access.txt | sort | uniq -c | sort -rn
```

**2. List Apache's 5xx lines. For each, did Tomcat or Apache produce the code?** (Use the Tomcat access log and the Apache error log.)

List the 5xx lines:

```bash
awk '$9 >= 500 {print $4, $7, $9}' apache/payment-access.txt
```

Compare `fail-web-2` at both hops:

```bash
grep -h 'fail-web-2' apache/payment-access.txt tomcat/localhost_access_log.txt
```

Compare `slow-web-1`:

```bash
grep -h 'slow-web-1' apache/payment-access.txt tomcat/localhost_access_log.txt
```

Compare `down-web-1`:

```bash
grep -h 'down-web-1' apache/payment-access.txt tomcat/localhost_access_log.txt
```

Read Apache's error log:

```bash
cat apache/payment-error.txt
```

**3. In `nginx/payment-access.txt`, which codes are 4xx/5xx, and what does `nginx/payment-error.txt` say about each?**

List the 4xx/5xx lines:

```bash
awk '$9 >= 400 {print $4, $7, $9}' nginx/payment-access.txt
```

Read Nginx's error log:

```bash
cat nginx/payment-error.txt
```

**4. Kong rejected two requests. Which, why, and did Tomcat see them? Then use the request ID of `down-api-1` to find its error line.**

List Kong's errors:

```bash
awk '$9 >= 400 {print $7, $9}' kong/access.txt
```

Check Tomcat for them:

```bash
grep -E 'nokey|blocked' tomcat/localhost_access_log.txt || echo "not in Tomcat"
```

Get the request ID of `down-api-1`:

```bash
grep 'down-api-1' kong/access.txt | awk '{print $NF}'
```

Find its error line:

```bash
grep 'b2a8762e31efd922a551d52f4fe9b916' kong/error.txt
```

**5. How many application exceptions are in `tomcat/localhost.txt`, and which application file and line should developers open?**

Count them:

```bash
grep -c SEVERE tomcat/localhost.txt
```

Show the first one:

```bash
grep -m1 -A3 SEVERE tomcat/localhost.txt
```

**6. From `tomcat/journal-tomcat.txt`: when did Tomcat stop and start, how long did startup take, and how long did `payment.war` take to deploy?**

```bash
grep -E 'Stopped|Started|Server startup in|deployWAR' tomcat/journal-tomcat.txt
```

**7. `slow-web-1` was logged by Apache as 502 at 12:27:29 and by Tomcat as 200 at 12:27:41. Explain both times and both codes.**

**8. How many Tomcat requests came through Nginx?**

```bash
grep -c 'HTTP/1.0"' tomcat/localhost_access_log.txt
```

---

# Part C — Microsoft IIS logs on Linux

- IIS = the web server built into Windows Server. Support teams often receive its logs and read them with Linux tools.

## 11. The IIS W3C log format

- Windows location: `C:\inetpub\logs\LogFiles\W3SVC<site-id>\`; one file per day, `u_exYYMMDD.log` (`u_` = times are UTC).
- Sample: `samples/iis/u_ex261111.txt` (11 Nov 2026); `.txt` only so the repository keeps it.
- `#` lines are **headers**. A new header block is written whenever logging restarts (site, application pool or server restart).
- Fields separated by single spaces; `+` replaces spaces inside a value, `-` = empty value — every line has the same number of fields.

Go to the IIS sample:

```bash
cd ~/ltm/middleware-labs/project-files/samples/iis
```

Show the first lines:

```bash
head -n 6 u_ex261111.txt
```

Show only header lines:

```bash
grep '^#' u_ex261111.txt
```

Check the file type and line endings:

```bash
file u_ex261111.txt
```

- Sample line:

```text
2026-11-11 05:12:25 10.20.30.15 POST /api/payment/charge - 443 - 10.20.60.12 PaymentMobile/4.2.1+(Android+14) - 500 0 0 15554
```

- **Always read the `#Fields:` line first** — it lists the columns. The 15 below are the classic IIS default; if an admin adds or removes fields, the column numbers change.

| awk field | W3C field | Meaning |
| --- | --- | --- |
| `$1` | `date` | Date, **UTC** |
| `$2` | `time` | Time the response finished, **UTC** |
| `$3` | `s-ip` | Server address |
| `$4` | `cs-method` | Method |
| `$5` | `cs-uri-stem` | Path, without query |
| `$6` | `cs-uri-query` | Query string, or `-` |
| `$7` | `s-port` | Server port (80, 443) |
| `$8` | `cs-username` | Authenticated user, or `-` |
| `$9` | `c-ip` | Client address |
| `$10` | `cs(User-Agent)` | Browser or program, spaces shown as `+` |
| `$11` | `cs(Referer)` | Linking page, or `-` |
| `$12` | `sc-status` | HTTP status |
| `$13` | `sc-substatus` | IIS detail number for the status |
| `$14` | `sc-win32-status` | Windows result code (0 = success) |
| `$15` | `time-taken` | Milliseconds from first byte received to last byte sent |

- Files from Windows usually have CRLF endings (`file` says `with CRLF line terminators`). Strip them before awk: `sed -i 's/\r$//' <file>`. The sample already uses Linux endings.

IIS status + sub-status + win32 codes in this sample:

| Code | Meaning | Usual owner |
| --- | --- | --- |
| `200.0` | OK | — |
| `304.0` | Not modified (browser cache is current) | — |
| `401.2` with win32 `5` | First anonymous request; IIS asks for credentials. Normal before a login | — |
| `401.1` with win32 `1326` | Logon failed: wrong user name or password | User / identity team, security if repeated |
| `403.14` | Directory listing denied, no default document | Web/middleware admin or content owner |
| `404.0` with win32 `2` | File not found | Content owner, or a broken link |
| `404.7` | File extension denied by request filtering (for example `.mdb`, `.cs`) | Security (probe) |
| `404.8` | Hidden namespace denied (for example `web.config`, `bin`, `App_Data`) | Security (probe) |
| `500.0` | Error inside the application or a module | Application developers |
| `503.0` | Service unavailable | Middleware admin first, then developers |

- A 503 from a **stopped application pool** is usually logged by the Windows HTTP driver in `C:\Windows\System32\LogFiles\HTTPERR\`, not the site log. A 503 in the site log means IIS or the application answered.

## 12. IIS exercises

- Start every command with `grep -v '^#'` so headers never mix with data. (Otherwise `$12 >= 500` also matches the `#Fields` line — awk compares it as text.)

**1. How many header blocks and requests are in the file? What does the second header block tell you?**

Count header blocks:

```bash
grep -c '^#Software' u_ex261111.txt
```

Show each block's date:

```bash
grep '^#Date' u_ex261111.txt
```

Count requests:

```bash
grep -vc '^#' u_ex261111.txt
```

**2. Count status and sub-status together.**

```bash
grep -v '^#' u_ex261111.txt | awk '{print $12"."$13}' | sort | uniq -c | sort -rn
```

**3. Who failed to log in, from where, and when?**

```bash
grep -v '^#' u_ex261111.txt | awk '$12 == 401 {print $2, $8, $9, $12"."$13, $14}'
```

**4. Which path gave 403.14?**

```bash
grep -v '^#' u_ex261111.txt | awk '$12 == 403 {print $2, $5, $12"."$13}'
```

**5. Find the scanner: which client caused the 404.7 and 404.8 lines, how many requests, which user agent, between which times?**

404s per client:

```bash
grep -v '^#' u_ex261111.txt | awk '$12 == 404 {print $9, $12"."$13}' | sort | uniq -c | sort -rn
```

Requests from that client:

```bash
grep -v '^#' u_ex261111.txt | awk '$9 == "203.0.113.77"' | wc -l
```

Its user agent:

```bash
grep -v '^#' u_ex261111.txt | awk '$9 == "203.0.113.77" {print $10}' | sort -u
```

Its first and last request:

```bash
grep -v '^#' u_ex261111.txt | awk '$9 == "203.0.113.77" {print $2, $5, $12"."$13}' | sed -n '1p;$p'
```

**6. Describe the 500 burst: which URL, how many, first and last time (UTC and IST), average and maximum time-taken.**

500s per URL:

```bash
grep -v '^#' u_ex261111.txt | awk '$12 == 500 {print $5}' | sort | uniq -c
```

First and last 500:

```bash
grep -v '^#' u_ex261111.txt | awk '$12 == 500 {print $2}' | sed -n '1p;$p'
```

Count, average and maximum time-taken:

```bash
grep -v '^#' u_ex261111.txt | awk '$12 == 500 {n++; sum += $15; if ($15 > max) max = $15} END {print n, int(sum / n), max}'
```

Convert the first time to IST:

```bash
TZ=Asia/Kolkata date -d '2026-11-11 05:12:25 UTC'
```

**7. Count errors per minute to see how the incident developed.**

```bash
grep -v '^#' u_ex261111.txt | awk '$12 >= 500 {print substr($2, 1, 5), $12}' | uniq -c
```

**8. The five slowest requests.**

```bash
grep -v '^#' u_ex261111.txt | sort -k15,15nr | head -n 5 | awk '{print $2, $4, $5, $12, $15}'
```

**9. Classify the morning's events: for each problem, name the producer and the team that should act.**

---

## 13. Classify the error and name the owner

Ask in order, for any error line:

1. **Which component wrote the status code?** Same code at both hops = backend; only at the frontend = frontend or gateway.
2. **Client problem (4xx) or server problem (5xx)?**
3. **Does the error log or journal explain it?**

| Evidence | Typical owner |
| --- | --- |
| `configtest`/`nginx -t`/`kong config parse` fails, wrong port, wrong root, permissions, service will not start | Web/middleware administrators |
| Stack trace, application 500, wrong WAR contents, missing class | Application developers |
| 401/403 from Kong or the web server for a real user, failed logons, scanner traffic | Security / identity team (and the API consumer for bad keys) |
| `Could not resolve host`, timeouts before any server log line, firewall drops | Network / DNS team |
| 429 from Kong | API consumer (slow down) or API product owner (raise the quota) |
| Disk full, CPU or memory exhausted | Platform / Linux administrators |

## 14. Save your evidence

Save the frontend and gateway lines:

```bash
sudo grep -h 'lab6-' /var/log/apache2/payment-access.log /var/log/nginx/payment-access.log /var/log/kong-lab/access.log | tee ~/lab/evidence/lab6-trace.txt
```

Append the Tomcat lines:

```bash
sudo sh -c 'grep -h "lab6-" /opt/tomcat/logs/localhost_access_log.*.txt' | tee -a ~/lab/evidence/lab6-trace.txt
```

Next: the [troubleshooting drills](08-troubleshooting-drills.md).

---

## Answers

### Part B

1. 39 lines: `28` × 200, `3` × 500, `2` × 503, `2` × 401, and one each of 502, 404, 403 and 301.
2. - `500` (`fail-web-1/2/3`): **Tomcat** produced them. Tomcat's access log shows the same request with 500, and `tomcat/localhost.txt` holds the stack trace.
   - `502` (`slow-web-1`): **Apache** produced it. Its error log says `(70007)The timeout specified has expired ... AH01102: error reading status line from remote server 127.0.0.1:8080`. Apache stopped waiting after `ProxyTimeout 10`.
   - `503` (`down-web-1/2`): **Apache** produced them. Its error log says `(111)Connection refused ... AH00957`. Tomcat has no line: it was stopped.
3. `403` `/private/` = `access forbidden by rule`; `401` `/admin/` without credentials = no error line (a normal login challenge); `504` `slow-ngx-1` = `upstream timed out ... while reading response header`; `400` `bad-1` = no Nginx error, the same 400 is in Tomcat's log, so the **application** rejected `ms=abc`; `502` `down-ngx-1/2` = `connect() failed (111: Connection refused)`.
4. `nokey-1` → 401 (no API key) and `blocked-1` → 403 (consumer not in the allowed ACL group). Tomcat has no line for either: Kong rejected them. `down-api-1` has ID `b2a8762e31efd922a551d52f4fe9b916`; the matching error line is `connect() failed (111: Connection refused)` to `127.0.0.1:8080`.
5. `6` (three through Apache, three through Kong). Developers should open `PaymentServlet.java`, line 15 (`lab.PaymentServlet.doGet`).
6. Stopped 12:27:41, started 12:27:45 IST; `Server startup in [550] milliseconds`; `payment.war` deployed in `[290] ms`.
7. Apache logs the arrival time (12:27:29) and gave up after 10 seconds, so the client got 502. Tomcat kept working, finished after 12 seconds and logged the finish time (12:27:41) with its own 200 — but nobody was waiting for that answer any more. Both logs are correct; the proxy timeout is shorter than the backend's response time.
8. `10` — `HTTP/1.0` marks requests forwarded by Nginx.

### Part C

1. `2` header blocks; `225` requests (233 lines minus 8 header lines). The second block at `05:20:11` UTC means logging restarted — the site or server was restarted after the incident.
2. `135` × 200.0, `22` × 503.0, `18` × 500.0, `18` × 304.0, `11` × 404.0, `5` × 404.8, `5` × 404.7, `5` × 401.2, `4` × 401.1, `2` × 403.14.
3. `CORP\ops.rahul` from `10.20.40.52` failed four times between `04:10:29` and `04:11:00` UTC (401.1, win32 1326 = bad user name or password). Each failure follows a normal 401.2 challenge. One other 401.2 at `03:52:11` was followed by a successful login of `CORP\ops.priya`.
4. `/payment-portal/downloads/`, twice (04:20:55 and 04:21:39). A folder with no default document and directory browsing disabled.
5. `203.0.113.77`: 8 × 404.0, 5 × 404.8, 5 × 404.7 = `18` requests, user agent `python-requests/2.31.0`, port 80, from `04:36:10` (`/.env`) to `04:36:22` (`/old/backup.mdb`). Request filtering blocked the dangerous paths. Report it to security.
6. `18` × 500, all `POST /api/payment/charge`, from `05:12:25` to `05:15:28` UTC = `10:42:25` to `10:45:28` IST. Average time-taken `21231` ms, maximum `28573` ms. `GET /api/payment/status` still answered 200 during the burst (but slowly, 0.9–3 s), so the charge function — probably a slow dependency behind it — was failing, not the whole site.
7. 500s: 4 at 05:12, 4 at 05:13, 6 at 05:14, 4 at 05:15. Then 503s: 8 at 05:16, 8 at 05:17, 6 at 05:18 (last at `05:18:58`). Then the restart at 05:20 and only normal traffic after it.
8. All five are `POST /api/payment/charge` 500s: 28573, 28377, 25052, 24451 and 24311 ms.
9. - Failed logons (401.1/1326): the user, or the identity/security team if they continue.
   - Scanner (404.7/404.8 from one outside address): security team.
   - 403.14 on `/downloads/`: web/middleware admin or content owner — expected behaviour or a broken link.
   - 500 burst with very high time-taken on one URL: application developers (with the times in IST, URL and time-taken), who check the dependency behind `charge`.
   - 503 period, ended by a restart: middleware admin restored service; developers still own the root cause.
