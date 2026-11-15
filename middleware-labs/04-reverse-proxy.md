# Lab 4 — put Apache and Nginx in front of Tomcat

**Time:** 75–90 minutes. **Prerequisite:** all three services healthy after Lab 3. **Deliverable:** the same Java application is reachable through either web server, and you can identify a failed hop.

```text
client -> Apache :80   -- /payment/ --> Tomcat 127.0.0.1:8080/payment/
client -> Nginx :8081 -- /payment/ --> Tomcat 127.0.0.1:8080/payment/
          both continue to serve the static portal themselves
```

## 1. Establish the baseline

```bash
systemctl is-active apache2 nginx tomcat
curl -s http://portal.example.test/health.txt
curl -s http://portal.example.test:8081/health.txt
curl -s http://127.0.0.1:8080/payment/status
curl -I http://portal.example.test/payment/status
curl -I http://portal.example.test:8081/payment/status
```

Expected: all services active, static health and direct Java health work; both public `/payment/status` requests still give 404 because forwarding is not configured yet.

## 2. Add Apache reverse proxying

```bash
sudo cp /etc/apache2/sites-available/payment-portal.conf ~/lab/backups/apache-before-proxy.conf
sudo a2enmod proxy proxy_http
cat ~/ltm/middleware-labs/project-files/config/apache-proxy.conf
sudo cp ~/ltm/middleware-labs/project-files/config/apache-proxy.conf /etc/apache2/sites-available/payment-portal.conf
sudo apache2ctl configtest && sudo systemctl restart apache2
curl -i http://portal.example.test/payment/status
curl -i http://portal.example.test/payment/balance
curl -i http://portal.example.test/health.txt
```

Expected: all return 200. We restart once here to load the newly enabled modules. Later site-only changes use reload.

Read the proxy additions:

```apache
ProxyRequests Off
ProxyPreserveHost On
ProxyTimeout 10
ProxyPass /payment/ http://127.0.0.1:8080/payment/ connectiontimeout=3 retry=0
ProxyPassReverse /payment/ http://127.0.0.1:8080/payment/
```

`ProxyRequests Off` keeps forward proxying disabled. `ProxyPass` forwards matching requests; `ProxyPassReverse` rewrites matching backend redirect headers. Both sides use a trailing slash. This is a request to another server, not a copy of Java files into Apache's document root.

## 3. Add Nginx reverse proxying

```bash
sudo cp /etc/nginx/sites-available/payment-portal ~/lab/backups/nginx-before-proxy.conf
cat ~/ltm/middleware-labs/project-files/config/nginx-proxy.conf
sudo cp ~/ltm/middleware-labs/project-files/config/nginx-proxy.conf /etc/nginx/sites-available/payment-portal
sudo nginx -t && sudo systemctl reload nginx
curl -i http://portal.example.test:8081/payment/status
curl -i http://portal.example.test:8081/payment/balance
curl -i http://portal.example.test:8081/health.txt
```

Expected: all 200. In the prepared config:

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

`proxy_pass` has **no URI part after port 8080**, so Nginx preserves `/payment/status`. Changing it to `http://127.0.0.1:8080/` would replace the matching `/payment/` prefix and send `/status`, the wrong context. A valid configuration can still forward the wrong URL.

`X-Forwarded-For` carries a client-address note. It does not automatically change Tomcat's logged remote address. This course leaves Tomcat's access-log peer as loopback; production client-IP processing requires carefully configured trusted proxies.

## 4. Trace one request through two logs

Terminal A:

```bash
sudo tail -f /var/log/apache2/payment-access.log /var/log/nginx/payment-access.log
```

Terminal B:

```bash
curl -i 'http://portal.example.test/payment/status?trace=apache-lab4'
curl -i 'http://portal.example.test:8081/payment/status?trace=nginx-lab4'
sudo sh -c 'grep "lab4" /opt/tomcat/logs/localhost_access_log.*.txt'
```

Expected: each request appears in its frontend log and in Tomcat's access log. Match time, path, query marker and status. Tomcat sees loopback as its TCP peer. Stop tail with Ctrl+C.

## 5. Fault exercise A — backend stopped

Keep the frontend services running:

```bash
sudo systemctl stop tomcat
systemctl is-active apache2 nginx
curl --max-time 5 -i http://portal.example.test:8081/payment/status
curl --max-time 5 -i http://portal.example.test/payment/status
curl --max-time 3 -i http://127.0.0.1:8080/payment/status
curl -i http://portal.example.test/health.txt
sudo tail -n 10 /var/log/nginx/payment-error.log
sudo tail -n 10 /var/log/apache2/payment-error.log
```

Expected: Nginx normally returns 502, Apache normally 503, direct Tomcat connection is refused, static portal health remains 200. The proxy error logs show a refused upstream connection. Exact codes can vary with configuration; the log is the proof.

Recovery:

```bash
sudo systemctl start tomcat
```

Wait for Tomcat startup, then:

```bash
curl -i http://127.0.0.1:8080/payment/status
curl -i http://portal.example.test/payment/status
curl -i http://portal.example.test:8081/payment/status
```

Expected: all 200.

## 6. Fault exercise B — backend is slower than the proxy timeout

The prepared application can deliberately wait before answering. Quote URLs containing `?` and `&`.

```bash
time curl --max-time 20 -i 'http://portal.example.test:8081/payment/slow?ms=15000'
sudo tail -n 5 /var/log/nginx/payment-error.log
curl --max-time 20 -i 'http://127.0.0.1:8080/payment/slow?ms=15000'
```

Expected: Nginx gives 504 after about 10 seconds; the direct request gives 200 after about 15 seconds. The error log says the upstream timed out while reading response headers. Here Tomcat is up; the proxy stopped waiting first.

`proxy_read_timeout` is an interval between upstream reads, not a universal end-to-end request deadline. This fixture waits without sending headers, making the timeout observable.

Recovery: use `/payment/status` again. No config change or restart is needed. Wait for the slow request to finish before collecting final log counts.

## 7. Fault exercise C — Apache points at the wrong port

```bash
sudo cp /etc/apache2/sites-available/payment-portal.conf ~/lab/backups/apache-proxy-good.conf
sudo sed -i 's/127.0.0.1:8080/127.0.0.1:8090/g' /etc/apache2/sites-available/payment-portal.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -i http://portal.example.test/payment/status
curl -i http://portal.example.test:8081/payment/status
curl -i http://127.0.0.1:8080/payment/status
sudo tail -n 8 /var/log/apache2/payment-error.log
```

Expected: Apache fails (normally 503), Nginx works, direct Tomcat works. The fault is the Apache-to-Tomcat hop. Configtest checks syntax, not whether port 8090 contains the correct application.

```bash
sudo cp ~/lab/backups/apache-proxy-good.conf /etc/apache2/sites-available/payment-portal.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -i http://portal.example.test/payment/status
```

## 8. Fault exercise D — an application error passes through

```bash
curl -i http://portal.example.test:8081/payment/fail
sudo tail -n 3 /var/log/nginx/payment-access.log
sudo sh -c 'tail -n 5 /opt/tomcat/logs/localhost_access_log.*.txt'
sudo sh -c 'grep -A8 "LAB simulated payment failure" /opt/tomcat/logs/localhost.*.log | tail -n 20'
```

Expected: 500 appears at both layers. Nginx successfully connected; the application threw the exception. Give developers the path, timestamp and stack trace. Recover by returning to `/payment/status`.

## 9. Practice challenge — diagnose without restarting everything

Ask your partner to choose one of the three faults above: stop Tomcat, mispoint Apache, or call `/slow`. You must first test the direct backend, then inspect the failing frontend's logs, identify the hop and restore only what is broken.

| Observation | Next evidence |
| --- | --- |
| Both proxies fail; direct backend refuses | Tomcat service, listener, journal |
| Apache fails; Nginx and direct backend work | Apache ProxyPass and site error log |
| Proxy times out; direct slow request eventually works | Timeout and application timing |
| All return 500 at `/fail` | Application exception and access logs |

A missing backend access-log line alone is not conclusive: logging can be delayed or disabled. Combine logs with a direct connection test.

## 10. Handoff

```bash
sudo apache2ctl configtest
sudo nginx -t
systemctl is-active apache2 nginx tomcat
curl -s http://portal.example.test/payment/status
curl -s http://portal.example.test:8081/payment/status
sudo cp /etc/apache2/sites-available/payment-portal.conf ~/lab/backups/apache-lab4-final.conf
sudo cp /etc/nginx/sites-available/payment-portal ~/lab/backups/nginx-lab4-final.conf
```

Both must return `Payment Service OK`. Open either portal in your laptop browser; its payment links now work. Continue to [Lab 5](05-api-gateway.md).

References: [Apache proxy directives](https://httpd.apache.org/docs/2.4/mod/mod_proxy.html), [Nginx proxy behavior and timeouts](https://nginx.org/en/docs/http/ngx_http_proxy_module.html).
