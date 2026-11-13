# 14 · Troubleshooting scenarios: break, read the log, fix, verify

**Time:** 90 min · **Work:** in pairs (one breaks, one diagnoses without looking)

**You will learn:** ten real failures, each worked the same way: **break → symptom → which log and the exact command → read the sample line part by part → cause → fix → verify**.

**Before you start:** topics 01–13. All scenarios use the `lab` site on **8083** (topic 11), so the shop keeps working.

---

## 14.0 · Prepare a known-good lab site

One clean copy to go back to after every scenario.

```bash
sudo mkdir -p /var/www/lab/docs /var/www/lab/empty /var/www/lab/api /srv/labfiles
echo "<h1>Lab home</h1>" | sudo tee /var/www/lab/index.html
echo "<h1>Docs index</h1>" | sudo tee /var/www/lab/docs/index.html
echo '{"api":"ok"}' | sudo tee /var/www/lab/api/status.json
echo "<h1>Manual</h1>" | sudo tee /srv/labfiles/manual.html
sudo tee /etc/nginx/lab.good <<'EOF'
server {
    listen 8083;
    server_name lab.example.com;
    root /var/www/lab;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
    location /files/ {
        alias /srv/labfiles/;
    }
    location /secret/ {
        deny all;
    }

    access_log /var/log/nginx/lab-access.log timed;
    error_log  /var/log/nginx/lab-error.log;
}
EOF
sudo cp /etc/nginx/lab.good /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -s http://lab.example.com:8083/
curl -s http://lab.example.com:8083/files/manual.html
```

- `/etc/nginx/lab.good` is outside `sites-enabled` and `conf.d`, so Nginx never loads it: it is only a backup.
- The access log uses the `timed` format from topic 06 (`rt=` and `host=` at the end).

**Reset after every scenario:**

```bash
sudo cp /etc/nginx/lab.good /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
```

### The reading method (every scenario)

1. **Client:** what exactly does `curl -i` (or the browser) get? Refused, timeout, which status?
2. **Config test:** `sudo nginx -t` — errors and warnings.
3. **Access log:** did the request arrive, which status, how long (`rt=`)?
4. **Error log:** why — the real path, the errno, the rule.
5. **State:** `systemctl status nginx`, `ss -lntp`, `nginx -T`.

---

## Scenario 1 · Missing semicolon and a typo

**Break**

```bash
sudo sed -i 's#    root /var/www/lab;#    root /var/www/lab#' /etc/nginx/sites-available/lab
sudo nginx -t
```

**Symptom:** `nginx -t` fails; a reload would be refused and the old config keeps running.

**Read**

```text
2026/11/13 00:48:35 [emerg] 7312#7312: invalid number of arguments in "root" directive in /etc/nginx/sites-enabled/lab:5
```

- `[emerg]`: Nginx refuses this config.
- `"root" directive … lab:5`: the file, and the line where the statement **ended**. The mistake is on line 4: look one line up.
- `invalid number of arguments`: without `;`, line 4 ran into line 5 (`root /var/www/lab index index.html;`).

**Fix and verify**

```bash
sudo cp /etc/nginx/lab.good /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
```

**Break again: a typo**

```bash
sudo sed -i 's#    index index.html;#    indx index.html;#' /etc/nginx/sites-available/lab
sudo nginx -t
sudo cp /etc/nginx/lab.good /etc/nginx/sites-available/lab
sudo nginx -t
```

```text
2026/11/13 00:48:36 [emerg] 7345#7345: unknown directive "indx" in /etc/nginx/sites-enabled/lab:5
```

- `unknown directive`: a spelling mistake, or a directive from a module that is not installed.

---

## Scenario 2 · Port already in use (98)

**Break:** someone moves the lab site to 8090 — Apache's port.

```bash
sudo sed -i 's/listen 8083;/listen 8090;/' /etc/nginx/sites-available/lab
sudo nginx -t
sudo systemctl reload nginx
curl -s -o /dev/null -w "%{http_code}\n" http://lab.example.com:8090/
```

**Symptom:** `nginx -t` says **ok**, the reload gives no error on screen, but 8090 still shows Apache's page.

**Read**

```bash
sudo tail -n 3 /var/log/nginx/error.log
sudo ss -lntp 'sport = :8090'
```

```text
2026/11/13 00:48:36 [emerg] 7056#7056: bind() to 0.0.0.0:8090 failed (98: Address already in use)
```

- In the **main** error log (start/reload messages go there, not to the site log).
- `bind()` = open a port. `98: Address already in use` = another program has it. `ss` names it: `apache2`.
- `nginx -t` checks only the text; it cannot know who owns a port.
- With `reload` the old config keeps serving. With `restart`, Nginx would **not start at all** and every Nginx site would be down.

**Fix and verify**

```bash
sudo cp /etc/nginx/lab.good /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
sudo ss -lntp | grep -E ":8083 |:8090 "
```

---

## Scenario 3 · Three kinds of "forbidden"

**Break**

```bash
sudo chmod 600 /var/www/lab/docs/index.html
curl -s -o /dev/null -w "file 600:   %{http_code}\n" http://lab.example.com:8083/docs/
sudo chmod 644 /var/www/lab/docs/index.html
sudo chmod 700 /var/www/lab/docs
curl -s -o /dev/null -w "folder 700: %{http_code}\n" http://lab.example.com:8083/docs/
sudo chmod 755 /var/www/lab/docs
curl -s -o /dev/null -w "no index:   %{http_code}\n" http://lab.example.com:8083/empty/
curl -s -o /dev/null -w "deny rule:  %{http_code}\n" http://lab.example.com:8083/secret/
```

**Read**

```bash
sudo tail -n 5 /var/log/nginx/lab-error.log
```

Sample lines (one per break, in order):

```text
2026/11/13 00:49:22 [error] 7896#7896: *1 "/var/www/lab/docs/index.html" is forbidden (13: Permission denied), client: 127.0.0.1, server: lab.example.com, request: "GET /docs/ HTTP/1.1", host: "lab.example.com:8083"
2026/11/13 00:48:38 [crit] 7323#7323: *18 open() "/var/www/lab/docs/" failed (13: Permission denied), client: 127.0.0.1, server: lab.example.com, request: "GET /docs/ HTTP/1.1", host: "lab.example.com:8083"
2026/11/13 00:48:38 [error] 7324#7324: *19 directory index of "/var/www/lab/empty/" is forbidden, client: 127.0.0.1, server: lab.example.com, request: "GET /empty/ HTTP/1.1", host: "lab.example.com:8083"
2026/11/13 00:48:38 [error] 7325#7325: *20 access forbidden by rule, client: 127.0.0.1, server: lab.example.com, request: "GET /secret/ HTTP/1.1", host: "lab.example.com:8083"
```

| Status | Log words | Cause | Fix |
|---|---|---|---|
| 403 | `"…/index.html" is forbidden (13: Permission denied)` or `open() … failed (13: …)` | www-data cannot **read the file** | `chmod 644` |
| 404 | `[crit] open() "/var/www/lab/docs/" failed (13: Permission denied)` | www-data cannot **enter the folder** (try_files then gives up: 404) | `chmod 755` folders; `namei -l <path>` shows which one |
| 403 | `directory index of "…" is forbidden` | folder has no `index.html`, autoindex off | add an index file (or autoindex if a listing is wanted) |
| 403 | `access forbidden by rule` | an `allow`/`deny` rule | the `location` rules |

- The status code alone cannot tell these apart. **The error log line can.**

**Verify**

```bash
namei -l /var/www/lab/docs/index.html
curl -s -o /dev/null -w "%{http_code}\n" http://lab.example.com:8083/docs/
```

---

## Scenario 4 · 404 from root instead of alias

**Break**

```bash
sudo sed -i 's#        alias /srv/labfiles/;#        root /srv/labfiles/;#' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null -w "%{http_code}\n" http://lab.example.com:8083/files/manual.html
```

**Read**

```bash
sudo tail -n 1 /var/log/nginx/lab-error.log
```

```text
2026/11/13 01:10:02 [error] 7101#7101: *12 open() "/srv/labfiles/files/manual.html" failed (2: No such file or directory), client: 127.0.0.1, server: lab.example.com, request: "GET /files/manual.html HTTP/1.1", host: "lab.example.com:8083"
```

- Compare the **path tried** with the real file: `/srv/labfiles/files/manual.html` vs `/srv/labfiles/manual.html`.
- The extra `/files/` proves `root` added the whole URL. `alias` replaces the location part.

**Fix and verify**

```bash
sudo cp /etc/nginx/lab.good /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -s http://lab.example.com:8083/files/manual.html
```

---

## Scenario 5 · The wrong website answers

**Break:** a new `promo` site is added on 8083 as `default_server`, and someone mistypes the lab name.

```bash
sudo mkdir -p /var/www/promo
echo "<h1>Promo</h1>" | sudo tee /var/www/promo/index.html
sudo tee /etc/nginx/sites-available/promo <<'EOF'
server {
    listen 8083 default_server;
    server_name promo.example.com;
    root /var/www/promo;
    access_log /var/log/nginx/promo-access.log;
}
EOF
sudo ln -s /etc/nginx/sites-available/promo /etc/nginx/sites-enabled/
sudo sed -i 's/server_name lab.example.com;/server_name lab.exmple.com;/' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -s http://lab.example.com:8083/
```

**Symptom:** `lab.example.com:8083` shows **Promo**. No error anywhere.

**Read**

```bash
sudo tail -n 1 /var/log/nginx/promo-access.log
sudo nginx -T 2>/dev/null | grep -E "^\s*(listen|server_name)"
```

- The request landed in **promo's** access log: the log file name tells you which server block answered.
- `nginx -T` shows no block with `server_name lab.example.com` on 8083 (only `lab.exmple.com`) → the request falls to `default_server` = promo.

**Fix and verify**

```bash
sudo cp /etc/nginx/lab.good /etc/nginx/sites-available/lab
sudo rm /etc/nginx/sites-enabled/promo
sudo nginx -t && sudo systemctl reload nginx
curl -s http://lab.example.com:8083/
```

---

## Scenario 6 · 413 Request Entity Too Large

**Break:** nothing to break; the default limit is 1 MB.

```bash
head -c 2000000 /dev/zero > ~/upload.bin
curl -s -o /dev/null -w "%{http_code}\n" -X POST --data-binary @$HOME/upload.bin http://lab.example.com:8083/
```

**Read**

```bash
sudo tail -n 1 /var/log/nginx/lab-error.log
sudo tail -n 1 /var/log/nginx/lab-access.log
```

```text
… [error] … client intended to send too large body: 2000000 bytes, client: 127.0.0.1, server: lab.example.com, request: "POST / HTTP/1.1", host: "lab.example.com:8083"
127.0.0.1 - - [13/Nov/2026:01:12:40 +0000] "POST / HTTP/1.1" 413 176 "-" "curl/8.5.0" rt=0.000 host=lab.example.com
```

- `client intended to send … 2000000 bytes`: the size from the request header; Nginx refused before reading the body.

**Fix and verify**

```bash
sudo sed -i 's#    index index.html;#    index index.html;\n    client_max_body_size 5m;#' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null -w "%{http_code}\n" -X POST --data-binary @$HOME/upload.bin http://lab.example.com:8083/
rm ~/upload.bin
```

- Now **405**: the size is accepted, but a static site cannot take a POST. In real life the upload goes to an application behind Nginx.

---

## Scenario 7 · 503 from rate limiting

**Break:** protect `/api/` with the `perip` zone from topic 05 (5 requests/s), with a small burst and no custom status.

```bash
sudo sed -i 's#    location /secret/ {#    location /api/ {\n        limit_req zone=perip burst=2 nodelay;\n        try_files $uri =404;\n    }\n    location /secret/ {#' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
for i in $(seq 1 10); do curl -s -o /dev/null -w "%{http_code} " http://lab.example.com:8083/api/status.json; done; echo
```

**Symptom:** about 3 × `200`, then `503 Service Unavailable`. A 503 usually means "back end down" — here nothing is down.

**Read**

```bash
sudo tail -n 1 /var/log/nginx/lab-error.log
sudo awk '$9 == 503' /var/log/nginx/lab-access.log | wc -l
```

```text
… [error] … limiting requests, excess: 2.960 by zone "perip", client: 127.0.0.1, server: lab.example.com, request: "GET /api/status.json HTTP/1.1" …
```

- `limiting requests` + `zone "perip"`: the rate limiter answered, not a crash.
- `excess: 2.960`: how far over the allowed burst this client was.
- Without `limit_req_status`, the default answer is **503**: easy to mistake for an outage.

**Fix and verify:** answer with 429 (honest "too many requests") and allow a bigger burst.

```bash
sudo sed -i 's#        limit_req zone=perip burst=2 nodelay;#        limit_req zone=perip burst=10 nodelay;\n        limit_req_status 429;#' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
for i in $(seq 1 15); do curl -s -o /dev/null -w "%{http_code} " http://lab.example.com:8083/api/status.json; done; echo
sudo cp /etc/nginx/lab.good /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
```

---

## Scenario 8 · Too many redirects (301 loop)

**Break**

```bash
sudo sed -i 's#    location / {#    return 301 http://lab.example.com:8083$request_uri;\n\n    location / {#' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -sS -L --max-redirs 5 -o /dev/null http://lab.example.com:8083/docs/
```

**Read**

```bash
curl -sI http://lab.example.com:8083/docs/ | grep -E "HTTP|Location"
sudo tail -n 3 /var/log/nginx/lab-access.log
```

- curl: `(47) Maximum (5) redirects followed`; browser: `ERR_TOO_MANY_REDIRECTS`.
- `Location:` equals the URL that was asked → a loop.
- Access log: the same URL with `301`, many times in the same second. The error log is empty: Nginx did what it was told.

**Fix and verify**

```bash
sudo cp /etc/nginx/lab.good /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -sI http://lab.example.com:8083/docs/ | head -n 1
```

---

## Scenario 9 · "The site is slow" — find it with $request_time

**Break:** a big download over a slow line (curl limits itself to 10 MB/s).

```bash
sudo fallocate -l 50M /var/www/lab/report.bin
for i in 1 2 3; do curl -s -o /dev/null http://lab.example.com:8083/; done
curl -s -o /dev/null --limit-rate 10M -w "client saw %{time_total} s\n" http://lab.example.com:8083/report.bin
```

**Read**

```bash
sudo tail -n 4 /var/log/nginx/lab-access.log
sudo awk -F'rt=' '$2+0 > 1 {print}' /var/log/nginx/lab-access.log
sudo grep -o '"[A-Z]* [^ ]*.*rt=[0-9.]*' /var/log/nginx/lab-access.log | awk -F'rt=' '{print $2, $1}' | sort -rn | head -n 3
```

```text
127.0.0.1 - - [13/Nov/2026:01:15:20 +0000] "GET /report.bin HTTP/1.1" 200 52428800 "-" "curl/8.5.0" rt=4.968 host=lab.example.com
```

- `rt=4.968`: Nginx spent about 5 s on this request; the home page shows `rt=0.000`.
- `52428800` bytes = 50 MB: the size explains the time. A slow **small** request would point at the disk or (later) a slow back end.
- `$request_time` runs from the first byte read until the last byte is handed to the network. Small files often show `0.000` even on a slow line (they fit in the network buffers).

**Fix and verify:** big files belong on a download server or CDN; remove the test file.

```bash
sudo rm /var/www/lab/report.bin
```

---

## Scenario 10 · Too many open files (24)

**Break:** one worker, 30 open files (topic 13.3).

```bash
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig
sudo sed -i 's/^worker_processes auto;/worker_processes 1;\nworker_rlimit_nofile 30;/' /etc/nginx/nginx.conf
sudo nginx -t && sudo systemctl restart nginx
ab -n 2000 -c 50 http://lab.example.com:8083/ | grep -E "Failed|Requests per second"
```

**Read**

```bash
sudo grep -rh "Too many open files" /var/log/nginx/ | tail -n 2
P=$(pgrep -f "nginx: worker" | head -n 1)
sudo grep "open files" /proc/$P/limits
```

```text
2026/11/13 00:46:28 [crit] 6932#6932: accept4() failed (24: Too many open files)
```

- `accept4()` = accept a new connection; `24` = the process hit its open-file limit; `[crit]` = serious.
- `/proc/<pid>/limits` shows the real limit of the running worker: `30`.
- `grep -r` over all logs: this line goes to the error log of the server block that owns the listening port, which may not be the one you expect.

**Fix and verify**

```bash
sudo cp /etc/nginx/nginx.conf.orig /etc/nginx/nginx.conf
sudo nginx -t && sudo systemctl restart nginx
P=$(pgrep -f "nginx: worker" | head -n 1)
sudo grep "open files" /proc/$P/limits
```

---

## Scenario summary

| # | Client sees | Look in | Key words |
|---|---|---|---|
| 1 | reload refused | `nginx -t` | `invalid number of arguments`, `unknown directive` |
| 2 | old site / nothing | main `error.log`, `ss` | `bind() … (98: Address already in use)` |
| 3 | 403 (or 404) | site error log | `(13: Permission denied)`, `directory index … forbidden`, `forbidden by rule` |
| 4 | 404 | site error log | `open() "<wrong path>" failed (2: …)` |
| 5 | wrong page | which access log got it, `nginx -T` | (no error) |
| 6 | 413 | site error log | `client intended to send too large body` |
| 7 | 503 / 429 | site error log | `limiting requests, excess … by zone` |
| 8 | too many redirects | access log, `curl -I` | same URL, `301` repeated |
| 9 | slow | access log | `rt=` large |
| 10 | slow / resets under load | any error log, `/proc/<pid>/limits` | `accept4() failed (24: Too many open files)` |

---

## Exercises (partner breaks, you diagnose)

1. Partner runs one scenario's **Break** block without telling you which. Using only the reading method, name the scenario and the evidence line.
2. Scenario 3 with the `/srv/labfiles` folder set to `700`. Which status and which log line? Which command shows the folder that blocks?
3. Scenario 7 with `limit_req_status 429` from the start. What changes in the access log?
4. In scenario 5, how could the access log alone have told you the request went to the wrong site if both sites used the same log file? (Hint: `host=` in the `timed` format.)

## Answers

1. Use the summary table.
2. `/files/manual.html` → **403** (the alias location has no try_files) with `[error] … open() "/srv/labfiles/manual.html" failed (13: Permission denied)`; `namei -l /srv/labfiles/manual.html` shows `drwx------ root root labfiles` and `Permission denied` under it.
3. Lines show `429` instead of `503`; `sudo awk '$9 == 429' /var/log/nginx/lab-access.log | wc -l` counts them.
4. Each line ends with `host=lab.example.com`; put `$server_name` in the format too, then the line shows both the name asked for and the block that answered.
