# 13 · Advanced logging: your own log format, slow pages, trace logs, rotation

**Time:** 50 min

**You will learn:** define one log format for all your sites, log the Host name, the real client behind a proxy and the time taken, make a deliberately slow page and find it in the log, the shared log for sites without their own, per-module log levels including the rewrite trace, and how rotation is scheduled and tested.

Uses the `admin` site from topic 05 (`admin.example.com` is already in `/etc/hosts` since 05.8).

---

## 13.1 · One log format for every site

- Topic 08 put a `LogFormat` inside one site. Better: define it **once**, server-wide, in its own file.

```bash
sudo vi /etc/apache2/conf-available/paybank-logformat.conf
```

Type:

```apache
LogFormat "%h %{X-Forwarded-For}i %u %t \"%r\" %>s %O %{Host}i \"%{User-Agent}i\" %D" paybank
```

```bash
sudo a2enconf paybank-logformat
sudo apache2ctl configtest && sudo systemctl reload apache2
```

- `paybank` at the end is the **name** of the format. Any site can now use it.

| Code | Logs | Why it helps |
|---|---|---|
| `%h` | client IP | who |
| `%{X-Forwarded-For}i` | the real client, when a proxy or load balancer sits in front | without it every request seems to come from the proxy |
| `%u` | user name (Basic auth) | who logged in |
| `%t` | time | when |
| `%r` | request line | what |
| `%>s` | final status | how it went |
| `%O` | bytes sent | size |
| `%{Host}i` | the Host header | which website, even in a shared log |
| `%{User-Agent}i` | the program | browser, app, bot |
| `%D` | time taken, **µs**, **last** on purpose | `$NF` in awk always finds it |

- `%{Name}i` logs any **request** header; `%{Name}o` logs any **response** header.

## 13.2 · Use it in the admin site

```bash
sudo cp /etc/apache2/sites-available/admin.conf /etc/apache2/sites-available/admin.conf.bak
sudo sed -i 's#admin-access.log combined#admin-access.log paybank#' /etc/apache2/sites-available/admin.conf
grep -n CustomLog /etc/apache2/sites-available/admin.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -s -o /dev/null http://admin.example.com/
curl -s -o /dev/null -H "X-Forwarded-For: 203.0.113.7" http://admin.example.com/nothing.html
sudo tail -n 2 /var/log/apache2/admin-access.log
```

Sample lines:

```text
127.0.0.1 - - [13/Nov/2026:10:40:42 +0530] "GET / HTTP/1.1" 200 340 admin.example.com "curl/8.5.0" 683
127.0.0.1 203.0.113.7 - [13/Nov/2026:10:40:42 +0530] "GET /nothing.html HTTP/1.1" 404 453 admin.example.com "curl/8.5.0" 109
```

| Field (awk) | Value | Means |
|---|---|---|
| `$1` | `127.0.0.1` | the machine that connected (here curl; later a proxy) |
| `$2` | `203.0.113.7` or `-` | the real client, if a proxy told us |
| `$9` | `404` | status |
| `$11` | `admin.example.com` | the website asked for |
| `$NF` | `109` | 109 µs = 0.1 ms |

- `$2` is `-` when no proxy sent the header.
- The reverse proxy module later in the course fills `X-Forwarded-For` for you.

## 13.3 · A slow page to find

Static files take well under a millisecond. Real slowness comes from programs behind the web server. Make a small one with **CGI** (Apache runs a script and sends its output):

```bash
sudo a2enmod cgid
sudo systemctl restart apache2
sudo tee /usr/lib/cgi-bin/slow.sh <<'EOF'
#!/bin/bash
sleep "${QUERY_STRING:-2}"
echo "Content-Type: text/plain"
echo
echo "slow answer after ${QUERY_STRING:-2} s"
EOF
sudo chmod 755 /usr/lib/cgi-bin/slow.sh
time curl -s "http://admin.example.com/cgi-bin/slow.sh?3"
curl -s -o /dev/null "http://admin.example.com/cgi-bin/slow.sh?1"
curl -s -o /dev/null http://admin.example.com/
```

- `/cgi-bin/` is mapped to `/usr/lib/cgi-bin/` by Ubuntu's `serve-cgi-bin.conf` (switched on by default; it works once `cgid` is enabled).
- `?3` = sleep 3 seconds. The script stands in for a slow database query.

Find the slow requests:

```bash
sudo awk '{print $NF, $7}' /var/log/apache2/admin-access.log | sort -n | tail -n 3
sudo awk '$NF > 1000000 {printf "%.1f s  %s %s\n", $NF/1000000, $4, $7}' /var/log/apache2/admin-access.log
```

- `1000000` µs = 1 s. The second command prints every request slower than 1 s, in seconds.
- The 3-second request shows about `3002301` µs; the 1-second one about `1001979`.
- `logrotate -d` (13.7) and these awk lines read the log; they never change it.

## 13.4 · Average time per URL

```bash
sudo awk '{split($7, p, "?"); sum[p[1]] += $NF; n[p[1]]++} END {for (u in sum) printf "%10.0f us  %4d req  %s\n", sum[u]/n[u], n[u], u}' /var/log/apache2/admin-access.log | sort -rn
```

- `split($7, p, "?")` cuts the query off, so `slow.sh?1` and `slow.sh?3` count as one URL.
- Read from the top: the slowest **kind** of request on average.

## 13.5 · One shared log for sites without their own

```bash
grep -v "^#" /etc/apache2/conf-enabled/other-vhosts-access-log.conf
grep -n "vhost_combined" /etc/apache2/apache2.conf
```

- Ubuntu logs every site that has **no** `CustomLog` of its own into `other_vhosts_access.log`.
- Its format `vhost_combined` starts with `%v:%p` = site name and port, so you can still tell sites apart.

Make a site without a CustomLog and watch:

```bash
sudo cp /etc/apache2/sites-available/reports.conf /etc/apache2/sites-available/reports.conf.bak
sudo sed -i '/CustomLog/d' /etc/apache2/sites-available/reports.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -s -o /dev/null http://localhost:8090/
sudo tail -n 1 /var/log/apache2/other_vhosts_access.log
```

Sample line:

```text
localhost:8090 127.0.0.1 - - [13/Nov/2026:10:41:02 +0530] "GET / HTTP/1.1" 200 287 "-" "curl/8.5.0"
```

- Field 1 is `name:port`, so every later field moves one to the right: status is `$10` here, not `$9`.
- Always look at a log's format before you count fields.

Put reports' own log back:

```bash
sudo cp /etc/apache2/sites-available/reports.conf.bak /etc/apache2/sites-available/reports.conf
grep -n CustomLog /etc/apache2/sites-available/reports.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
```

## 13.6 · LogLevel per module: the rewrite trace

- `LogLevel warn` hides how Apache decided. Turn one module up, in one site only.
- `mod_rewrite` has its own levels `trace1` … `trace8`: the old `RewriteLog` of Apache 2.2.

In `admin.conf`, inside the VirtualHost, add:

```apache
    LogLevel warn rewrite:trace3
    RewriteEngine On
    RewriteRule ^/old/(.*)$ /new/$1 [R=302,L]
```

```bash
sudo mkdir -p /var/www/admin/new
echo "<h1>new page</h1>" | sudo tee /var/www/admin/new/index.html
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -sI http://admin.example.com/old/index.html | grep -E "HTTP|Location"
sudo grep "rewrite:trace" /var/log/apache2/admin-error.log | tail -n 6 | sed 's/.*initial\] //'
```

Sample lines (after the `sed`, which cuts the long prefix):

```text
applying pattern '^/old/(.*)$' to uri '/old/index.html'
rewrite '/old/index.html' -> '/new/index.html'
explicitly forcing redirect with http://admin.example.com/new/index.html
setting lastsub to rule with output /new/$1
escaping http://admin.example.com/new/index.html for redirect
redirect to http://admin.example.com/new/index.html [REDIRECT/302]
```

- One line per decision: which pattern was tried on which path, what it became, and why.
- A rule that "does nothing" shows `applying pattern … to uri …` with **no** `rewrite` line after it: the pattern did not match.
- Switch the trace off when done: trace levels write several lines per request. Remove the LogLevel line (the rewrite rule stays):

```bash
sudo sed -i '/rewrite:trace3/d' /etc/apache2/sites-available/admin.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
```

Other useful per-module levels:

| LogLevel | Shows |
|---|---|
| `authz_core:debug` | each Require decision (topic 08) |
| `auth_basic:debug` | each login check |
| `ssl:info` | TLS handshakes and their errors |
| `rewrite:trace3` | each rewrite step |

## 13.7 · How rotation is scheduled and tested

```bash
systemctl list-timers logrotate.timer --no-pager
cat /etc/logrotate.d/apache2
sudo logrotate -d /etc/logrotate.d/apache2 2>&1 | grep -E "rotating pattern|considering log|does not need" | head -n 8
```

- A systemd **timer** runs logrotate once a day.
- `logrotate -d` = **dry run**: prints what it would do and changes nothing. Use it after every edit of a logrotate file.
- `*.log` in the first line covers every site log you made, because they all live in `/var/log/apache2`.
- A log written **outside** that folder (e.g. `/srv/logs/app.log`) is never rotated until you add a logrotate file for it: a classic cause of a full disk.

Where does the space go?

```bash
sudo du -sh /var/log/apache2/* | sort -h | tail -n 5
df -h /var/log
```

---

## Exercises

1. Add `%{Referer}i` to the paybank format (before the user agent) and prove it with `curl -e http://example.com/`.
2. Run `slow.sh?2` five times and `slow.sh?4` once. Which line of 13.4 shows the average, and what is it roughly?
3. Which file logs a site that has no CustomLog, and how is it different from `access.log`?
4. A rewrite rule seems to be ignored. Which LogLevel do you set, and what line proves the pattern did not match?
5. A team writes logs to `/srv/logs/payment.log`. Why will the disk fill up, and how do you check what logrotate would do?

## Answers

1. `… %O %{Host}i \"%{Referer}i\" \"%{User-Agent}i\" %D`; `curl -s -o /dev/null -e http://example.com/ http://admin.example.com/`; the line contains `"http://example.com/"`.
2. The `/cgi-bin/slow.sh` line of the 13.4 command. The six new requests alone average 2.3 s (5 × 2 s + 1 × 4 s = 14 s over 6); with the requests from 13.3 included the line shows about 1.8 s over 10 requests.
3. `other_vhosts_access.log`, format `vhost_combined`: starts with `name:port`, so status is field 10.
4. `LogLevel warn rewrite:trace3`; `applying pattern '…' to uri '…'` with no `rewrite '…' -> '…'` after it.
5. `/etc/logrotate.d/apache2` covers only `/var/log/apache2/*.log`; add a logrotate file for `/srv/logs/*.log` and test it with `sudo logrotate -d <file>`.
