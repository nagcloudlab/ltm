# 06 · Logs: read, customise, analyse, rotate

**Time:** 40 min

**You will learn:** the two logs and per-site logs, the access-log fields, error-log lines and levels, a custom log format with response time, conditional and buffered logging, analysis one-liners, and log rotation.

---

## 06.1 · Which logs exist

```bash
ls -l /var/log/nginx/
grep -n -E "access_log|error_log" /etc/nginx/nginx.conf /etc/nginx/sites-available/*
```

| Log | Written | Answers |
|---|---|---|
| `access.log` (or `shop-access.log` per site) | every request | **what** happened |
| `error.log` (or `shop-error.log`) | problems, start/stop | **why** |

A site's `access_log` line **replaces** the main access log for that site.

## 06.2 · Generate traffic

```bash
for p in / /style.css /nothing /nothing.png /images/ /admin/ /old.html /docs; do curl -s -o /dev/null http://localhost:8081$p; done
curl -s -o /dev/null -X POST http://localhost:8081/
curl -s -o /dev/null -A "Monitor/1.0" http://localhost:8081/health.json
sudo tail -n 10 /var/log/nginx/shop-access.log
```

## 06.3 · The access-log line

Nginx's default format `combined` is the **same as Apache's**. Sample line, with field numbers:

```text
127.0.0.1 - - [11/Nov/2026:10:20:31 +0530] "GET /nothing HTTP/1.1" 404 61 "-" "curl/8.5.0"
1         2 3 4 + 5                         6 + 7 + 8                9   10  11  12
```

| # | Field | Nginx variable |
|---|---|---|
| 1 | client IP | `$remote_addr` |
| 3 | user (basic auth) | `$remote_user` |
| 4–5 | time | `$time_local` |
| 6–8 | request | `$request` |
| **9** | **status** | `$status` |
| 10 | bytes | `$body_bytes_sent` |
| 11 | referer | `$http_referer` |
| 12 | user agent | `$http_user_agent` |

So every Apache one-liner works unchanged.

## 06.4 · The error-log line and its levels

```bash
sudo tail -n 5 /var/log/nginx/shop-error.log
```

Sample line:

```text
2026/11/11 10:20:31 [error] 2102#2102: *15 open() "/var/www/shop/nothing.png" failed (2: No such file or directory), client: 127.0.0.1, server: shop.example.com, request: "GET /nothing.png HTTP/1.1", host: "localhost:8081"
```

| Part | Example | Means |
|---|---|---|
| time | `2026/11/11 10:20:31` | server **local** time, no time zone shown |
| level | `[error]` | how serious (list below) |
| pid#tid | `2102#2102` | worker process id # thread id |
| connection | `*15` | connection number: the same `*15` on several lines = one visitor's story |
| message | `open() "…/nothing.png" failed` | what Nginx tried: the **real path on disk** |
| errno | `(2: No such file or directory)` | why, in Linux words |
| `client:` | `127.0.0.1` | who asked |
| `server:` | `shop.example.com` | which server block answered (empty = a block with no `server_name`) |
| `request:` · `host:` | `"GET /nothing.png HTTP/1.1"` · `"localhost:8081"` | what was asked, and the Host header |

- **Why `/nothing.png` and not `/nothing`?** `/nothing` goes through `try_files $uri $uri/ =404;`. try_files checks quietly and writes **no** error-log line; only the access log shows the 404.
- `/nothing.png` matches the regex location for `.png` (topic 04), which has no try_files, so Nginx really opens the file and logs the failure.

| errno | Means | Status |
|---|---|---|
| `2: No such file or directory` | file missing | 404 |
| `13: Permission denied` | www-data cannot read the file | 403 |
| `[crit] … (13: Permission denied)` on a folder | www-data cannot enter the folder (try_files) | 404 |
| `directory index of … is forbidden` | folder, no index, no autoindex | 403 |
| `access forbidden by rule` | allow/deny | 403 |

Levels, from most to least detail: `debug info notice warn error crit alert emerg`. The default is `error`. Missing files are logged at `error`; to see why a request was redirected or matched a location, raise one site temporarily:

```nginx
    error_log /var/log/nginx/shop-error.log info;
```

(`debug` needs a debug build; `info` and `notice` are enough for most work.) Put it back to the default afterwards.

## 06.5 · A custom format with response time

```bash
sudo tee /etc/nginx/conf.d/logformat.conf <<'EOF'
log_format timed '$remote_addr - $remote_user [$time_local] "$request" '
                 '$status $body_bytes_sent "$http_referer" "$http_user_agent" '
                 'rt=$request_time host=$host';
EOF
sudo sed -i 's#access_log /var/log/nginx/shop-access.log;#access_log /var/log/nginx/shop-access.log timed;#' /etc/nginx/sites-available/shop
sudo nginx -t && sudo systemctl reload nginx
for i in 1 2 3; do curl -s -o /dev/null http://localhost:8081/; done
sudo tail -n 3 /var/log/nginx/shop-access.log
```

| Variable | Means |
|---|---|
| `$request_time` | seconds from first byte read to last byte sent (`0.002`) |
| `$host` | the site name asked for |
| `$upstream_response_time` | time the **backend** took (reverse proxy module) |
| `$request_length` | request size, including headers |
| `$ssl_protocol` | TLS version (https, Day 2) |

`log_format` must be in `http` (that is why it lives in `conf.d`); `access_log` in the server uses it by name.

Slowest requests:

```bash
sudo grep -o 'rt=[0-9.]*.*' /var/log/nginx/shop-access.log | sort -t= -k2 -n | tail -n 3
```

## 06.6 · Log only what matters, and log less

Skip health-check noise:

```bash
sudo tee /etc/nginx/conf.d/lognoise.conf <<'EOF'
map $request_uri $loggable {
    /health.json  0;
    default       1;
}
EOF
sudo sed -i 's#access_log /var/log/nginx/shop-access.log timed;#access_log /var/log/nginx/shop-access.log timed if=$loggable;#' /etc/nginx/sites-available/shop
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null http://localhost:8081/health.json
sudo tail -n 1 /var/log/nginx/shop-access.log
```

The health check no longer appears. `map` sets `$loggable` to 0 for that URL; `if=$loggable` skips lines where it is 0.

| Option | Use |
|---|---|
| `access_log off;` | in a location: no logging (e.g. `/favicon.ico`) |
| `access_log … buffer=32k flush=5s;` | write in batches: less disk work on busy servers |

## 06.7 · Analysis one-liners

```bash
L=/var/log/nginx/shop-access.log
```

| Question | Command |
|---|---|
| status breakdown | `sudo cut -d' ' -f9 $L \| sort \| uniq -c \| sort -rn` |
| all 4xx/5xx with paths | `sudo awk '$9 >= 400 {print $9, $7}' $L \| sort \| uniq -c \| sort -rn` |
| top clients | `sudo cut -d' ' -f1 $L \| sort \| uniq -c \| sort -rn \| head` |
| requests per minute | `sudo cut -d' ' -f4 $L \| cut -d: -f2,3 \| sort \| uniq -c` |
| who triggered rate limiting | `sudo awk '$9 == 429 {print $1}' $L \| sort \| uniq -c` |
| errors by reason | `sudo grep -o 'failed ([0-9]*: [^)]*)\|forbidden by rule\|is forbidden' /var/log/nginx/shop-error.log \| sort \| uniq -c` |

## 06.8 · Rotation

```bash
cat /etc/logrotate.d/nginx
```

| Line | Means |
|---|---|
| `daily` · `rotate 14` | daily, keep 14 |
| `compress` · `delaycompress` | gzip old files, keep yesterday's plain |
| `postrotate … invoke-rc.d nginx rotate` | tells Nginx to **reopen** its log files (same as `nginx -s reopen`) |

```bash
sudo logrotate -f /etc/logrotate.d/nginx
ls -l /var/log/nginx/
```

Without the reopen step Nginx keeps writing to the renamed file (Linux topic 07, the open-file trap).

---

## Exercises

1. Which site name appears in each line of your `timed` log? Count requests per site name.
2. Show every request slower than 0.5 s (generate one with `curl --limit-rate 10k` on a big file).
3. Stop logging requests for `/style.css` only.
4. A user reports a 403 on `/images/` at 10:20. Which error-log line explains it?
5. After rotation, why must Nginx reopen its logs?

## Answers

1. `sudo grep -o 'host=[^ ]*' /var/log/nginx/shop-access.log | sort | uniq -c`.
2. `sudo fallocate -l 50M /var/www/shop/big.bin; curl -s --limit-rate 10M -o /dev/null http://localhost:8081/big.bin` (about 5 s), then `sudo awk -F'rt=' '$2+0 > 0.5' /var/log/nginx/shop-access.log`; delete `big.bin` afterwards. A small file (2 MB) still shows `rt=0.000`: it fits in the network buffers, and `$request_time` stops when the last byte is handed to the kernel.
3. `location = /style.css { access_log off; }`.
4. `directory index of "/var/www/shop/images/" is forbidden` (when autoindex is off).
5. It still holds the old file open and would keep writing into the rotated file; reopen makes it write to the new `access.log`.
