# Lab 4 — Put Apache and Nginx in front of Tomcat

- **Needs:** all three services healthy after [Lab 3](03-tomcat.md)
- **You build:** the same Java app reachable through either web server, and the skill to spot the failed hop

```text
client -> Apache :80   -- /payment/ --> Tomcat 127.0.0.1:8080/payment/
client -> Nginx :8081 -- /payment/ --> Tomcat 127.0.0.1:8080/payment/
          both continue to serve the static portal themselves
```

## 1. Establish the baseline

- Prove everything works directly before adding forwarding.

Check all three services:

```bash
systemctl is-active apache2 nginx tomcat
```

Check the Apache portal:

```bash
curl -s http://portal.example.test/health.txt
```

Check the Nginx portal:

```bash
curl -s http://portal.example.test:8081/health.txt
```

Call Tomcat directly:

```bash
curl -s http://127.0.0.1:8080/payment/status
```

Try the payment path through Apache:

```bash
curl -I http://portal.example.test/payment/status
```

Try the payment path through Nginx:

```bash
curl -I http://portal.example.test:8081/payment/status
```

- **Expected:** all active; static health and direct Java health work; both `/payment/status` requests through the portals give **404** (no forwarding yet).

## 2. Add Apache reverse proxying

Back up the current site:

```bash
sudo cp /etc/apache2/sites-available/payment-portal.conf ~/lab/backups/apache-before-proxy.conf
```

Enable the proxy modules:

```bash
sudo a2enmod proxy proxy_http
```

Read the prepared site file:

```bash
cat ~/ltm/middleware-labs/project-files/config/apache-proxy.conf
```

Install it:

```bash
sudo cp ~/ltm/middleware-labs/project-files/config/apache-proxy.conf /etc/apache2/sites-available/payment-portal.conf
```

Test the config, then restart (loads the new modules):

```bash
sudo apache2ctl configtest && sudo systemctl restart apache2
```

Call the status page through Apache:

```bash
curl -i http://portal.example.test/payment/status
```

Call the balance page through Apache:

```bash
curl -i http://portal.example.test/payment/balance
```

Check static content still works:

```bash
curl -i http://portal.example.test/health.txt
```

- **Expected:** all 200.
- **Why restart:** new modules need a restart; later site-only changes use reload.

The proxy lines in the site file:

```apache
ProxyRequests Off
ProxyPreserveHost On
ProxyTimeout 10
ProxyPass /payment/ http://127.0.0.1:8080/payment/ connectiontimeout=3 retry=0
ProxyPassReverse /payment/ http://127.0.0.1:8080/payment/
```

- `ProxyRequests Off` — forward proxying stays disabled.
- `ProxyPass` — forwards matching requests to Tomcat.
- `ProxyPassReverse` — rewrites backend redirect headers.
- Both sides end with a trailing slash.
- This is a request to another server, not a copy of Java files into Apache's document root.

## 3. Add Nginx reverse proxying

Back up the current site:

```bash
sudo cp /etc/nginx/sites-available/payment-portal ~/lab/backups/nginx-before-proxy.conf
```

Read the prepared site file:

```bash
cat ~/ltm/middleware-labs/project-files/config/nginx-proxy.conf
```

Install it:

```bash
sudo cp ~/ltm/middleware-labs/project-files/config/nginx-proxy.conf /etc/nginx/sites-available/payment-portal
```

Test the config, then reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Call the status page through Nginx:

```bash
curl -i http://portal.example.test:8081/payment/status
```

Call the balance page through Nginx:

```bash
curl -i http://portal.example.test:8081/payment/balance
```

Check static content still works:

```bash
curl -i http://portal.example.test:8081/health.txt
```

- **Expected:** all 200.

The proxy block in the site file:

```nginx
location /payment/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 3s;
    proxy_read_timeout 10s;
}
```

- `proxy_pass` has **no URI after port 8080**, so Nginx keeps `/payment/status`.
- `http://127.0.0.1:8080/` would replace `/payment/` and send `/status` — the wrong context. A valid config can still forward the wrong URL.
- `X-Forwarded-For` carries the client address as a note; Tomcat still logs loopback as the peer. Production client-IP handling needs carefully configured trusted proxies.

## 4. Trace one request through two logs

**Terminal A** — follow both frontend access logs (Ctrl+C when done):

```bash
sudo tail -f /var/log/apache2/payment-access.log /var/log/nginx/payment-access.log
```

**Terminal B** — send a marked request through Apache:

```bash
curl -i 'http://portal.example.test/payment/status?trace=apache-lab4'
```

Send a marked request through Nginx:

```bash
curl -i 'http://portal.example.test:8081/payment/status?trace=nginx-lab4'
```

Wait for Tomcat's access log to flush:

```bash
sleep 10
```

Find both requests in Tomcat's access log:

```bash
sudo sh -c 'grep "lab4" /opt/tomcat/logs/localhost_access_log.*.txt'
```

- **Expected:** each request appears in its frontend log and in Tomcat's log. Match time, path, query marker and status.
- Tomcat sees loopback as its peer.
- The Nginx-forwarded line shows `HTTP/1.0` — Nginx uses HTTP/1.0 upstream unless `proxy_http_version` is set.

## 5. Fault exercise A — backend stopped

**Break** — stop only Tomcat:

```bash
sudo systemctl stop tomcat
```

**Observe** — confirm the frontends are still up:

```bash
systemctl is-active apache2 nginx
```

Call through Nginx:

```bash
curl --max-time 5 -i http://portal.example.test:8081/payment/status
```

Call through Apache:

```bash
curl --max-time 5 -i http://portal.example.test/payment/status
```

Call Tomcat directly:

```bash
curl --max-time 3 -i http://127.0.0.1:8080/payment/status
```

Check static content:

```bash
curl -i http://portal.example.test/health.txt
```

Read the Nginx error log:

```bash
sudo tail -n 10 /var/log/nginx/payment-error.log
```

Read the Apache error log:

```bash
sudo tail -n 10 /var/log/apache2/payment-error.log
```

- **Expected:** Nginx normally 502, Apache normally 503, direct Tomcat refused, static health 200.
- Sample lines (Nginx, then Apache):

```text
[error] connect() failed (111: Connection refused) while connecting to upstream, ... upstream: "http://127.0.0.1:8080/payment/status"
[proxy:error] (111)Connection refused: AH00957: http: attempt to connect to 127.0.0.1:8080 (127.0.0.1:8080) failed
```

- Exact codes vary with configuration; the log is the proof.

**Recover** — start Tomcat:

```bash
sudo systemctl start tomcat
```

**Verify** (after Tomcat starts) — direct:

```bash
curl -i http://127.0.0.1:8080/payment/status
```

Through Apache:

```bash
curl -i http://portal.example.test/payment/status
```

Through Nginx:

```bash
curl -i http://portal.example.test:8081/payment/status
```

- **Expected:** all 200.

## 6. Fault exercise B — backend is slower than the proxy timeout

- The app can deliberately wait before answering. Quote URLs that contain `?` or `&`.

**Break** — request a 15-second answer through Nginx:

```bash
time curl --max-time 20 -i 'http://portal.example.test:8081/payment/slow?ms=15000'
```

**Observe** — read the Nginx error log:

```bash
sudo tail -n 5 /var/log/nginx/payment-error.log
```

Request the same directly from Tomcat:

```bash
curl --max-time 20 -i 'http://127.0.0.1:8080/payment/slow?ms=15000'
```

- **Expected:** Nginx gives 504 after about 10 s; direct request gives 200 after about 15 s.
- Error log: `upstream timed out (110: Connection timed out) while reading response header from upstream`
- Through Apache the same URL gives `502 Proxy Error` after about 10 s (`ProxyTimeout 10`).
- **Why:** Tomcat is up; the proxy stopped waiting first. `proxy_read_timeout` is the gap between upstream reads, not an end-to-end deadline — this app sends no headers while waiting, so the timeout shows.
- **Recover:** use `/payment/status` again; no config change or restart. Let the slow request finish before collecting final log counts.

## 7. Fault exercise C — Apache points at the wrong port

**Break** — back up the good site:

```bash
sudo cp /etc/apache2/sites-available/payment-portal.conf ~/lab/backups/apache-proxy-good.conf
```

Point Apache at port 8090:

```bash
sudo sed -i 's/127.0.0.1:8080/127.0.0.1:8090/g' /etc/apache2/sites-available/payment-portal.conf
```

Test and reload:

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
```

**Observe** — through Apache:

```bash
curl -i http://portal.example.test/payment/status
```

Through Nginx:

```bash
curl -i http://portal.example.test:8081/payment/status
```

Directly:

```bash
curl -i http://127.0.0.1:8080/payment/status
```

Read the Apache error log:

```bash
sudo tail -n 8 /var/log/apache2/payment-error.log
```

- **Expected:** Apache fails (normally 503); Nginx and direct Tomcat work → the fault is the Apache-to-Tomcat hop.
- **Why:** configtest checks syntax, not whether port 8090 has the right application.

**Recover** — restore the good site:

```bash
sudo cp ~/lab/backups/apache-proxy-good.conf /etc/apache2/sites-available/payment-portal.conf
```

Test and reload:

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
```

**Verify:**

```bash
curl -i http://portal.example.test/payment/status
```

## 8. Fault exercise D — an application error passes through

**Break** — call the failing page through Nginx:

```bash
curl -i http://portal.example.test:8081/payment/fail
```

**Observe** — Nginx access log:

```bash
sudo tail -n 3 /var/log/nginx/payment-access.log
```

Wait for Tomcat's access log to flush:

```bash
sleep 10
```

Tomcat access log:

```bash
sudo sh -c 'tail -n 5 /opt/tomcat/logs/localhost_access_log.*.txt'
```

Stack trace:

```bash
sudo sh -c 'grep -A8 "LAB simulated payment failure" /opt/tomcat/logs/localhost.*.log | tail -n 20'
```

- **Expected:** 500 at both layers. Nginx connected fine; the application threw the exception.
- Give developers the path, timestamp and stack trace.
- **Recover:** return to `/payment/status`.

## 9. Practice challenge — diagnose without restarting everything

- Your partner picks one fault: stop Tomcat, mispoint Apache, or call `/slow`.
- You: test the direct backend first, read the failing frontend's logs, name the hop, restore only what is broken.

| Observation | Next evidence |
| --- | --- |
| Both proxies fail; direct backend refuses | Tomcat service, listener, journal |
| Apache fails; Nginx and direct backend work | Apache ProxyPass and site error log |
| Proxy times out; direct slow request eventually works | Timeout and application timing |
| All return 500 at `/fail` | Application exception and access logs |

- A missing backend access-log line alone proves nothing (logging can be delayed or disabled) — combine logs with a direct connection test.

## 10. Handoff

Test the Apache config:

```bash
sudo apache2ctl configtest
```

Test the Nginx config:

```bash
sudo nginx -t
```

Check all three services:

```bash
systemctl is-active apache2 nginx tomcat
```

Payment through Apache:

```bash
curl -s http://portal.example.test/payment/status
```

Payment through Nginx:

```bash
curl -s http://portal.example.test:8081/payment/status
```

Save the final Apache site:

```bash
sudo cp /etc/apache2/sites-available/payment-portal.conf ~/lab/backups/apache-lab4-final.conf
```

Save the final Nginx site:

```bash
sudo cp /etc/nginx/sites-available/payment-portal ~/lab/backups/nginx-lab4-final.conf
```

- **Expected:** both return `Payment Service OK`. The payment links in either portal now work in your laptop browser.
- Continue to [Lab 5](05-api-gateway.md).
- References: [Apache proxy directives](https://httpd.apache.org/docs/2.4/mod/mod_proxy.html), [Nginx proxy behavior and timeouts](https://nginx.org/en/docs/http/ngx_http_proxy_module.html).
