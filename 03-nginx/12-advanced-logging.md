# 12 · Advanced logging: JSON, errors-only logs, levels, rotation by hand

**Time:** 40 min

**You will learn:** a JSON access log (easy for tools), a second log that keeps only errors, two logs for one site, error-log levels in practice, how log rotation really works (`mv` + `nginx -s reopen`), and buffered logs.

**Before you start:** topic 06 (formats, `map`, `if=`) and topic 11 (the `lab` site on 8083).

---

## 12.1 · A JSON access log

- The `combined` line is easy for people and for `awk`. Log tools (ELK, Loki, Splunk) prefer **JSON**: every field has a name.
- `escape=json` makes Nginx escape quotes and odd characters so every line is valid JSON.

```bash
sudo tee /etc/nginx/conf.d/logjson.conf <<'EOF'
log_format json escape=json '{"time":"$time_iso8601","ip":"$remote_addr","method":"$request_method","uri":"$request_uri","status":$status,"bytes":$body_bytes_sent,"rt":$request_time,"host":"$host","ua":"$http_user_agent"}';
EOF
sudo sed -i 's#    access_log /var/log/nginx/lab-access.log;#    access_log /var/log/nginx/lab-access.log;\n    access_log /var/log/nginx/lab-access.json json;#' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null http://lab.example.com:8083/
curl -s -o /dev/null "http://lab.example.com:8083/nope?q=1"
sudo tail -n 2 /var/log/nginx/lab-access.json
```

Sample line:

```text
{"time":"2026-11-13T00:40:03+00:00","ip":"127.0.0.1","method":"GET","uri":"/nope?q=1","status":404,"bytes":146,"rt":0.000,"host":"lab.example.com","ua":"curl/8.5.0"}
```

- `$time_iso8601` includes the time zone (`+00:00`): no guessing.
- Two `access_log` lines in one server = **two files** for every request (people read one, tools read the other).

Read JSON with Python (already on Ubuntu) or with grep:

```bash
sudo cat /var/log/nginx/lab-access.json | python3 -c 'import sys, json; [print(r["status"], r["rt"], r["uri"]) for r in map(json.loads, sys.stdin)]'
sudo grep -o '"status":[0-9]*' /var/log/nginx/lab-access.json | sort | uniq -c
```

## 12.2 · A log that keeps only errors

```bash
sudo tee /etc/nginx/conf.d/logerrors.conf <<'EOF'
map $status $is_error {
    ~^[45]  1;
    default 0;
}
EOF
sudo sed -i 's#    access_log /var/log/nginx/lab-access.json json;#    access_log /var/log/nginx/lab-access.json json;\n    access_log /var/log/nginx/lab-errors.log combined if=$is_error;#' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null http://lab.example.com:8083/
curl -s -o /dev/null http://lab.example.com:8083/missing
sudo cat /var/log/nginx/lab-errors.log
```

- `~^[45]` = a regex: status starting with 4 or 5.
- On a busy site `lab-errors.log` is small: open it first when something breaks.

## 12.3 · Error-log levels in practice

| Level | You see, for example |
|---|---|
| `emerg` | `bind() … (98: Address already in use)`, config errors at start |
| `alert` | `worker process 5623 exited on signal 9` |
| `crit` | `accept4() failed (24: Too many open files)`, `(13: Permission denied)` on a folder |
| `error` | `open() … failed (2: …)`, `access forbidden by rule`, `limiting requests` |
| `warn` | `conflicting server name`, `delaying request` (limit_req with delay) |
| `notice` | `rewrite_log` lines, start/stop signals |
| `info` | `client closed keepalive connection`, TLS handshake failures |
| `debug` | everything; needs the `nginx-debug` binary, not used here |

- The level you set is the **minimum**: `error` (the default) shows `error`, `crit`, `alert`, `emerg`.

Raise the lab site to `info` for a moment:

```bash
sudo sed -i 's#    error_log  /var/log/nginx/lab-error.log;#    error_log  /var/log/nginx/lab-error.log info;#' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null http://lab.example.com:8083/
sudo tail -n 2 /var/log/nginx/lab-error.log
sudo sed -i 's#    error_log  /var/log/nginx/lab-error.log info;#    error_log  /var/log/nginx/lab-error.log;#' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
```

Sample line:

```text
2026/11/13 00:40:05 [info] 5492#5492: *31 client 127.0.0.1 closed keepalive connection
```

- `info` is normal traffic noise. Use it for minutes, not days.

## 12.4 · Where does a message go? The site's log or the main log

- A line about a request goes to the `error_log` of the **server block** that handled it (`shop-error.log`, `lab-error.log`).
- Start, stop, reload, `bind()` and worker crashes go to the **main** `/var/log/nginx/error.log`.
- A server block **without** its own `error_log` writes to the main log. The `stats` site (topic 03) has no `error_log` and no `server_name`, so its lines land in `error.log` with `server: ` (empty).

```bash
curl -s -o /dev/null http://localhost:8082/missing.html
sudo grep -h "server: ," /var/log/nginx/error.log | tail -n 2
sudo grep -h -E "\[emerg\]|\[alert\]" /var/log/nginx/error.log | tail -n 3
```

> When you do not find the line you expect: `sudo grep -rh "the words" /var/log/nginx/` searches every Nginx log at once.

## 12.5 · Rotation by hand: why reopen matters

```bash
sudo ls -li /var/log/nginx/lab-access.log
sudo mv /var/log/nginx/lab-access.log /var/log/nginx/lab-access.log.1
curl -s -o /dev/null http://lab.example.com:8083/after-move
sudo ls -l /var/log/nginx/ | grep lab-access
sudo tail -n 1 /var/log/nginx/lab-access.log.1
```

- After `mv`, Nginx still holds the **same open file** (same inode). New lines go into `lab-access.log.1`; `lab-access.log` does not exist.

```bash
sudo nginx -s reopen
curl -s -o /dev/null http://lab.example.com:8083/after-reopen
sudo ls -l /var/log/nginx/ | grep lab-access
sudo tail -n 1 /var/log/nginx/lab-access.log
```

- `nginx -s reopen` (sent as signal `USR1`) closes and reopens every log: a new `lab-access.log` appears and gets the new line.
- This is exactly what logrotate's `postrotate … invoke-rc.d nginx rotate` does every night.

```bash
sudo logrotate -d /etc/logrotate.d/nginx 2>&1 | grep -E "considering log|does not need rotating|rotating pattern" | head -n 8
```

- `-d` = dry run: shows what logrotate **would** do, changes nothing.

## 12.6 · Buffered logs

```nginx
    access_log /var/log/nginx/lab-access.log combined buffer=32k flush=5s;
```

- Nginx collects lines in memory and writes them in batches: less disk work on busy servers.
- Side effect: the newest lines appear up to 5 s late. Remember it when "my request is not in the log yet".

---

## Exercises

1. Count requests per status code from `lab-access.json` with Python.
2. Add `"ref":"$http_referer"` to the JSON format and prove the field appears.
3. Which log file receives `bind() to 0.0.0.0:80 failed`? Which receives `access forbidden by rule` for the shop?
4. You moved a log away and the new file never appears. What one command fixes it?
5. Why is `info` level not kept on in production?

## Answers

1. `sudo cat /var/log/nginx/lab-access.json | python3 -c 'import sys, json, collections; print(collections.Counter(json.loads(l)["status"] for l in sys.stdin))'`.
2. Edit `/etc/nginx/conf.d/logjson.conf`, `nginx -t`, reload, curl with `-e http://test/`, `tail -n 1` shows `"ref":"http://test/"`.
3. `bind()` → main `/var/log/nginx/error.log`; the shop's 403 → `shop-error.log`.
4. `sudo nginx -s reopen` (or `sudo systemctl reload nginx`).
5. A line for every closed connection and handshake: the disk fills and real errors are hard to find.
