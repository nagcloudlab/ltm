# Troubleshooting drills

- **Needs:** [Lab 6](07-reading-logs.md) completed; full stack from Labs 1–5 running
- **You build:** for each fault — the symptom, the log line that proves it, the cause, the fix and the owning team

Every drill uses the same skeleton:

- **Break** — create a **deliberate fault**. Run only one drill at a time.
- **Observe** — what a user or monitor sees, and where to look.
- **Sample line** — what the evidence looks like (your times and process numbers will differ).
- **Cause** / **Fix** / **Verify** — always fix and verify before the next drill.
- **Owner** — **web/middleware admin** (Apache, Nginx, Tomcat, Kong config and services), **application developers** (WAR, code, response times), **network** (names, routing, firewalls), **security** (credentials, access policy), **platform** (Linux disk, CPU, memory).

## 0. Starting state

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

- Use gateway stage 3 (keys and ACL, no rate limit), so a quota cannot hide other faults.

Install stage 3:

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/03-acl.yml /etc/kong-lab/kong.yml
```

Validate and reload Kong:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

### The health check

- Run it now and after every fix.

Services active:

```bash
systemctl is-active apache2 nginx tomcat payment-kong
```

Apache:

```bash
curl -s -o /dev/null -w 'apache %{http_code}\n' http://portal.example.test/payment/status
```

Nginx:

```bash
curl -s -o /dev/null -w 'nginx  %{http_code}\n' http://portal.example.test:8081/payment/status
```

Tomcat direct:

```bash
curl -s -o /dev/null -w 'tomcat %{http_code}\n' http://127.0.0.1:8080/payment/status
```

Kong:

```bash
curl -s -o /dev/null -w 'kong   %{http_code}\n' -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

- **Expected:** four `active` lines and four `200` codes. Do not start a drill until this is true.

---

## Drill 1 — Apache configuration typo

A directive in the site file is misspelled.

- **Break** — back up the site file:

```bash
sudo cp /etc/apache2/sites-available/payment-portal.conf ~/lab/backups/drill1-apache.conf
```

Misspell `ProxyPass`:

```bash
sudo sed -i 's/^    ProxyPass \/payment/    ProxyPas \/payment/' /etc/apache2/sites-available/payment-portal.conf
```

- **Observe** — test the configuration:

```bash
sudo apache2ctl configtest
```

Try to reload:

```bash
sudo systemctl reload apache2
```

Is Apache still running?

```bash
systemctl is-active apache2
```

Does it still answer?

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://portal.example.test/payment/status
```

  - `configtest` and the reload fail, but Apache stays `active` and answers `200` — it keeps the last good config in memory. The danger is the **next** full restart, which will not start.
  - Also look at: `sudo journalctl -u apache2 -n 10 --no-pager`.
- **Sample line:**

```text
AH00526: Syntax error on line 21 of /etc/apache2/sites-enabled/payment-portal.conf:
Invalid command 'ProxyPas', perhaps misspelled or defined by a module not included in the server configuration
```

- **Cause:** typo in the site file.
- **Fix** — restore the backup:

```bash
sudo cp ~/lab/backups/drill1-apache.conf /etc/apache2/sites-available/payment-portal.conf
```

Test and reload:

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
```

- **Verify:**

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://portal.example.test/payment/status
```

- **Owner:** web/middleware admin.

## Drill 2 — Nginx and Apache both want port 80

Someone re-enables Nginx's default site, which listens on port 80.

- **Break** — enable the default site:

```bash
sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
```

- **Observe** — syntax test:

```bash
sudo nginx -t
```

Restart Nginx:

```bash
sudo systemctl restart nginx
```

Is it running?

```bash
systemctl is-active nginx
```

Nginx on 8081:

```bash
curl -s -o /dev/null -w 'nginx  %{http_code}\n' http://portal.example.test:8081/health.txt
```

Apache on 80:

```bash
curl -s -o /dev/null -w 'apache %{http_code}\n' http://portal.example.test/health.txt
```

  - `nginx -t` says syntax OK, yet the restart fails. Nginx is `failed`, so port **8081 is down too** (`000` = no connection). Apache on 80 is unaffected.
  - Look at: `sudo journalctl -u nginx -n 12 --no-pager`, then `sudo ss -lntp 'sport = :80'` to see who owns the port.
- **Sample line** (journal, then `ss`):

```text
nginx[6108]: nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)
```

```text
LISTEN 0      511                *:80              *:*    users:(("apache2",pid=6039,fd=4),("apache2",pid=6038,fd=4))
```

- **Cause:** two services configured for the same port. A syntax test does not check whether a port is free.
- **Fix** — remove the link (the site file stays in `sites-available`):

```bash
sudo rm /etc/nginx/sites-enabled/default
```

Test and restart:

```bash
sudo nginx -t && sudo systemctl restart nginx
```

- **Verify** — running again:

```bash
systemctl is-active nginx
```

Port 8081 answers:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://portal.example.test:8081/health.txt
```

- **Owner:** web/middleware admin.

## Drill 3 — password file unreadable by the web server

The password files lose their group read permission. Predict first: is `/admin/` a 401 or a 500?

- **Break:**

```bash
sudo chmod 600 /etc/apache2/payment.htpasswd /etc/nginx/payment.htpasswd
```

- **Observe** (enter your Lab 1 admin password when curl asks) — Apache, no password:

```bash
curl -s -o /dev/null -w 'apache, no password:   %{http_code}\n' http://portal.example.test/admin/
```

Apache, with password:

```bash
curl -u admin -s -o /dev/null -w 'apache, with password: %{http_code}\n' http://portal.example.test/admin/
```

Nginx, no password:

```bash
curl -s -o /dev/null -w 'nginx,  no password:   %{http_code}\n' http://portal.example.test:8081/admin/
```

Nginx, with password:

```bash
curl -u admin -s -o /dev/null -w 'nginx,  with password: %{http_code}\n' http://portal.example.test:8081/admin/
```

  - **401** without credentials (server only asks for a login, never reads the file); **500** with correct credentials (server must read the file and cannot).
  - Look at: `sudo tail -n 3 /var/log/apache2/payment-error.log` and `sudo tail -n 3 /var/log/nginx/payment-error.log`; then `sudo -u www-data cat /etc/apache2/payment.htpasswd`.
- **Sample line** (Apache, then Nginx):

```text
[authn_file:error] [pid 6039:tid 281473020588320] (13)Permission denied: [client 127.0.0.1:46854] AH01620: Could not open password file: /etc/apache2/payment.htpasswd
```

```text
2026/11/15 12:29:25 [crit] 6134#6134: *3 open() "/etc/nginx/payment.htpasswd" failed (13: Permission denied), client: 127.0.0.1, server: portal.example.test, request: "GET /admin/ HTTP/1.1", host: "portal.example.test:8081"
```

- **Cause:** mode `600 root:www-data` — the `www-data` group lost read access.
- **Fix:**

```bash
sudo chmod 640 /etc/apache2/payment.htpasswd /etc/nginx/payment.htpasswd
```

- **Verify** — check the mode:

```bash
ls -l /etc/apache2/payment.htpasswd /etc/nginx/payment.htpasswd
```

Apache login:

```bash
curl -u admin -s -o /dev/null -w '%{http_code}\n' http://portal.example.test/admin/
```

Nginx login:

```bash
curl -u admin -s -o /dev/null -w '%{http_code}\n' http://portal.example.test:8081/admin/
```

- **Owner:** web/middleware admin.

## Drill 4 — the site name does not resolve

The lab name disappears from `/etc/hosts`.

- **Break** — back up `/etc/hosts`:

```bash
sudo cp /etc/hosts ~/lab/backups/hosts-before-drill4
```

Remove the lab name:

```bash
sed '/portal\.example\.test/d' ~/lab/backups/hosts-before-drill4 | sudo tee /etc/hosts > /dev/null
```

- **Observe** — request by name:

```bash
curl -I http://portal.example.test/health.txt
```

Look the name up:

```bash
getent hosts portal.example.test || echo "name not found"
```

Same request by address, with the `Host` header:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: portal.example.test' http://127.0.0.1/health.txt
```

  - curl fails before any HTTP exchange; no web server log line exists. By address with the right `Host` header it works.
  - **If the name still resolves** (`127.0.0.1 localhost portal.example.test`): the local resolver (`systemd-resolved`) still holds the old `/etc/hosts` for a second or two. Repeat both commands.
- **Sample line:**

```text
curl: (6) Could not resolve host: portal.example.test
```

- **Cause:** name resolution, not the web server. In a company: a DNS record or a client's hosts file.
- **Fix:**

```bash
sudo cp ~/lab/backups/hosts-before-drill4 /etc/hosts
```

- **Verify** — name resolves:

```bash
getent hosts portal.example.test
```

Site answers:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://portal.example.test/health.txt
```

- **Owner:** network (DNS) team.

## Drill 5 — Tomcat will not start: broken `server.xml`

One XML closing tag in `server.xml` is damaged.

- **Break** — back up `server.xml`:

```bash
sudo cp /opt/tomcat/conf/server.xml ~/lab/backups/drill5-server.xml
```

Damage `</Engine>`:

```bash
sudo sed -i 's#</Engine>#</Engin>#' /opt/tomcat/conf/server.xml
```

- **Observe** — restart and print its exit code:

```bash
sudo systemctl restart tomcat
echo "restart exit code: $?"
```

Wait:

```bash
sleep 8
```

State:

```bash
systemctl is-active tomcat
```

Status summary:

```bash
systemctl status tomcat --no-pager | head -n 6
```

  - Restart returns `0`, but the service is `activating (auto-restart)` and never becomes active. Through the proxies: Apache 503, Nginx 502, Kong 502. Directly: connection refused.
  - Look at: `sudo journalctl -u tomcat -n 40 --no-pager | grep -E 'SEVERE|SAXParseException'`.
  - `Restart=on-failure` makes systemd retry every 3 seconds; the same error repeats in the journal.
- **Sample line:**

```text
SEVERE [main] org.apache.tomcat.util.digester.Digester.fatalError Parse fatal error at line [160] column [7]
org.xml.sax.SAXParseException; systemId: file:/opt/tomcat/conf/server.xml; lineNumber: 160; columnNumber: 7; The element type "Engine" must be terminated by the matching end-tag "</Engine>".
SEVERE [main] org.apache.catalina.startup.Catalina.start Cannot start server, server instance is not configured
```

- **Cause:** invalid XML in a server config file. The message gives file, line and column.
- **Fix** — restore the backup:

```bash
sudo cp ~/lab/backups/drill5-server.xml /opt/tomcat/conf/server.xml
```

Restart:

```bash
sudo systemctl restart tomcat
```

- **Verify:** wait about 20 seconds, then run [the health check](#the-health-check).
- **Owner:** web/middleware admin.

## Drill 6 — Tomcat will not start: wrong `JAVA_HOME`

The unit points at a Java folder that does not exist.

- **Break** — change `JAVA_HOME` in the unit:

```bash
sudo sed -i 's#JAVA_HOME=/usr/lib/jvm/java-21-lab#JAVA_HOME=/usr/lib/jvm/java-17-lab#' /etc/systemd/system/tomcat.service
```

Reload systemd:

```bash
sudo systemctl daemon-reload
```

Restart Tomcat:

```bash
sudo systemctl restart tomcat
```

- **Observe** — wait:

```bash
sleep 5
```

State:

```bash
systemctl is-active tomcat
```

Read the journal:

```bash
sudo journalctl -u tomcat -n 6 --no-pager
```

See which Java folders exist:

```bash
ls -l /usr/lib/jvm/
```

  - From outside, same as drill 5: never active, proxies return 502/503. No Java stack trace this time — Java never started.
- **Sample line:**

```text
catalina.sh[6413]: The JAVA_HOME environment variable is not defined correctly
catalina.sh[6413]: JAVA_HOME=/usr/lib/jvm/java-17-lab
catalina.sh[6413]: This environment variable is needed to run this program
```

- **Cause:** the unit names a path that does not exist (common after a Java upgrade or a unit copied from another server).
- **Fix** — restore the unit:

```bash
sudo cp ~/ltm/middleware-labs/project-files/config/tomcat.service /etc/systemd/system/tomcat.service
```

Reload systemd:

```bash
sudo systemctl daemon-reload
```

Restart Tomcat:

```bash
sudo systemctl restart tomcat
```

- **Verify:** wait about 20 seconds, then run [the health check](#the-health-check).
- **Owner:** web/middleware admin.

## Drill 7 — WAR deployed with the wrong name

A release is copied with a version in its file name.

- **Break** — remove the current WAR:

```bash
sudo rm /opt/tomcat/webapps/payment.war
```

Wait for undeploy:

```bash
sleep 15
```

Install the versioned WAR:

```bash
sudo install -o tomcat -g tomcat -m 640 ~/ltm/middleware-labs/project-files/apps/payment.war /opt/tomcat/webapps/payment-1.2.war
```

Wait for deploy:

```bash
sleep 15
```

- **Observe** — list webapps:

```bash
sudo ls /opt/tomcat/webapps/
```

Via Apache:

```bash
curl -s -o /dev/null -w 'apache %{http_code}\n' http://portal.example.test/payment/status
```

Via Kong:

```bash
curl -s -o /dev/null -w 'kong   %{http_code}\n' -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

At the new context:

```bash
curl -s -o /dev/null -w 'new context %{http_code}\n' http://127.0.0.1:8080/payment-1.2/status
```

  - Tomcat is healthy, but `/payment/...` is **404** through every path; the app answers at `/payment-1.2/`.

Deployment lines in the journal:

```bash
sudo journalctl -u tomcat --since '2 minutes ago' --no-pager | grep -E 'deployWAR|undeploy'
```

Tomcat's access log (wait 10 seconds for it to be written):

```bash
sudo sh -c 'tail -n 3 /opt/tomcat/logs/localhost_access_log.*.txt'
```

- **Sample line:**

```text
INFO [Catalina-utility-2] org.apache.catalina.startup.HostConfig.undeploy Undeploying context [/payment]
INFO [Catalina-utility-2] org.apache.catalina.startup.HostConfig.deployWAR Deploying web application archive [/opt/tomcat/webapps/payment-1.2.war]
127.0.0.1 - - [15/Nov/2026:12:31:08 +0530] "GET /payment/status HTTP/1.1" 404 770
```

- **Cause:** the WAR file name sets the URL context: `payment-1.2.war` → `/payment-1.2`. The 404 comes from **Tomcat**, not the proxies.
- **Fix** — remove the versioned WAR:

```bash
sudo rm /opt/tomcat/webapps/payment-1.2.war
```

Install with the agreed name:

```bash
sudo install -o tomcat -g tomcat -m 640 ~/ltm/middleware-labs/project-files/apps/payment.war /opt/tomcat/webapps/payment.war
```

Wait for deploy:

```bash
sleep 15
```

- **Verify** — list webapps, then run [the health check](#the-health-check):

```bash
sudo ls /opt/tomcat/webapps/
```

- **Owner:** web/middleware admin (deployment step); tell the release team to keep the agreed file name.

## Drill 8 — Tomcat stopped

The backend is down.

- **Break:**

```bash
sudo systemctl stop tomcat
```

- **Observe** — Apache:

```bash
curl -s -o /dev/null -w 'apache %{http_code}\n' 'http://portal.example.test/payment/status?trace=drill8'
```

Nginx:

```bash
curl -s -o /dev/null -w 'nginx  %{http_code}\n' 'http://portal.example.test:8081/payment/status?trace=drill8'
```

Kong:

```bash
curl -s -o /dev/null -w 'kong   %{http_code}\n' -H 'apikey: demo-key-123' 'http://127.0.0.1:8000/api/payment/status?trace=drill8'
```

Static page:

```bash
curl -s -o /dev/null -w 'static %{http_code}\n' http://portal.example.test/health.txt
```

  - Apache **503**, Nginx **502**, Kong **502**; static pages still 200.

Apache error log:

```bash
sudo tail -n 2 /var/log/apache2/payment-error.log
```

Nginx error log:

```bash
sudo tail -n 1 /var/log/nginx/payment-error.log
```

Kong error log:

```bash
sudo tail -n 1 /var/log/kong-lab/error.log
```

- **Sample line** (Apache, then Nginx):

```text
[proxy:error] [pid 5596:tid 281472711389472] (111)Connection refused: AH00957: http: attempt to connect to 127.0.0.1:8080 (127.0.0.1:8080) failed
2026/11/15 12:27:41 [error] 5582#5582: *17 connect() failed (111: Connection refused) while connecting to upstream, client: 127.0.0.1, server: portal.example.test, request: "GET /payment/status?trace=drill8 HTTP/1.1", upstream: "http://127.0.0.1:8080/payment/status?trace=drill8", host: "portal.example.test:8081"
```

- **Cause:** nothing listens on 127.0.0.1:8080. Three codes, one cause — each product reports a refused backend its own way.
- **Fix:**

```bash
sudo systemctl start tomcat
```

- **Verify:** wait about 20 seconds, then run [the health check](#the-health-check).
- **Owner:** web/middleware admin — find out *why* it stopped: `sudo journalctl -u tomcat`.

## Drill 9 — slow backend

The application waits 12 seconds — longer than the 10-second proxy timeouts.

- **Break** — slow request via Nginx:

```bash
time curl -s -o /dev/null -w 'nginx  %{http_code}\n' 'http://portal.example.test:8081/payment/slow?ms=12000&trace=drill9'
```

Via Apache:

```bash
time curl -s -o /dev/null -w 'apache %{http_code}\n' 'http://portal.example.test/payment/slow?ms=12000&trace=drill9'
```

Via Kong:

```bash
time curl -s -w '\n' -H 'apikey: demo-key-123' 'http://127.0.0.1:8000/api/payment/slow?ms=12000&trace=drill9'
```

- **Observe:** after about 10 seconds — Nginx **504**, Apache **502** (Apache reports this timeout as a proxy error), Kong **504** with body `"The upstream server is timing out"`.

Nginx error log:

```bash
sudo tail -n 1 /var/log/nginx/payment-error.log
```

Apache error log:

```bash
sudo tail -n 2 /var/log/apache2/payment-error.log
```

Wait for Tomcat's access log:

```bash
sleep 10
```

Find the request in Tomcat:

```bash
sudo sh -c 'grep drill9 /opt/tomcat/logs/localhost_access_log.*.txt'
```

- **Sample line** (Nginx, Apache, Tomcat):

```text
2026/11/15 12:27:39 [error] 5577#5577: *13 upstream timed out (110: Connection timed out) while reading response header from upstream, client: 127.0.0.1, server: portal.example.test, request: "GET /payment/slow?ms=12000&trace=drill9 HTTP/1.1", upstream: "http://127.0.0.1:8080/payment/slow?ms=12000&trace=drill9", host: "portal.example.test:8081"
[proxy_http:error] [pid 5596:tid 281472728297760] (70007)The timeout specified has expired: [client 127.0.0.1:55264] AH01102: error reading status line from remote server 127.0.0.1:8080
127.0.0.1 - - [15/Nov/2026:12:27:41 +0530] "GET /payment/slow?ms=12000&trace=drill9 HTTP/1.0" 200 32
```

- **Cause:** backend up but slower than the proxy timeout. Tomcat logs **200** — it finished, but the proxy had stopped waiting.
- **Fix:** nothing to undo — only `/slow` is slow.
- **Verify:** run [the health check](#the-health-check).
- **Owner:** application developers (why is it slow?); web/middleware admin only if the timeout itself is wrong.

## Drill 10 — invalid Kong configuration, then a careless restart

YAML indentation is broken, then Kong is restarted without validating.

- **Break** — back up `kong.yml`:

```bash
sudo cp /etc/kong-lab/kong.yml ~/lab/backups/drill10-kong.yml
```

Break the indentation:

```bash
sudo sed -i 's/^    url: http/   url: http/' /etc/kong-lab/kong.yml
```

Look at the top of the file:

```bash
sudo head -n 6 /etc/kong-lab/kong.yml
```

Validate (this is the warning):

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf
```

Restart anyway:

```bash
sudo systemctl restart payment-kong
```

- **Observe** — state:

```bash
systemctl is-active payment-kong
```

Call the API:

```bash
curl -s -o /dev/null -w 'kong %{http_code}\n' -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

  - Parse fails. After the restart the gateway is **down**: `000` (connection refused). A reload instead would have kept the old config running.
  - Look at: the parse output and `sudo journalctl -u payment-kong -n 12 --no-pager`.
- **Sample line** (parse, then journal):

```text
Error: Failed parsing:
failed parsing declarative configuration: 5:4: did not find expected '-' indicator
```

```text
kong[6768]: nginx: [error] init_by_lua error: /usr/local/share/lua/5.1/kong/init.lua:731: error parsing declarative config file /etc/kong-lab/kong.yml:
kong[6768]: failed parsing declarative configuration: 5:4: did not find expected '-' indicator
systemd[1]: Failed to start payment-kong.service - Payment lab Kong API gateway.
```

  - `5:4` = line 5, column 4. YAML depends on exact spaces.
- **Cause:** invalid declarative configuration, applied with a restart.
- **Fix** — restore the backup:

```bash
sudo cp ~/lab/backups/drill10-kong.yml /etc/kong-lab/kong.yml
```

Validate, then restart:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl restart payment-kong
```

- **Verify** — wait:

```bash
sleep 5
```

State, then run [the health check](#the-health-check):

```bash
systemctl is-active payment-kong
```

- **Owner:** web/middleware admin (gateway team).

## Drill 11 — Kong points at the wrong backend port

A valid file with the wrong upstream.

- **Break** — back up `kong.yml`:

```bash
sudo cp /etc/kong-lab/kong.yml ~/lab/backups/drill11-kong.yml
```

Change the port to 8090:

```bash
sudo sed -i 's#http://127.0.0.1:8080/payment#http://127.0.0.1:8090/payment#' /etc/kong-lab/kong.yml
```

Validate and reload:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

- **Observe** — wait:

```bash
sleep 4
```

Via Kong:

```bash
curl -s -w '\n' -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

Tomcat direct:

```bash
curl -s -o /dev/null -w 'direct tomcat %{http_code}\n' http://127.0.0.1:8080/payment/status
```

Kong error log:

```bash
sudo tail -n 1 /var/log/kong-lab/error.log
```

  - Kong **502** (`"An invalid response was received from the upstream server"`); Tomcat answers 200 directly; web proxies still work.
- **Sample line:**

```text
2026/11/15 12:32:20 [error] 6643#0: *1320 connect() failed (111: Connection refused) while connecting to upstream, client: 127.0.0.1, server: kong, request: "GET /api/payment/status HTTP/1.1", upstream: "http://127.0.0.1:8090/payment/status", host: "127.0.0.1:8000", request_id: "da16a1466c50173a21d6..."
```

  - `upstream:` shows the wrong port. A successful parse only proves the file is valid YAML with known settings.
- **Cause:** wrong service URL in the gateway configuration.
- **Fix** — restore the backup:

```bash
sudo cp ~/lab/backups/drill11-kong.yml /etc/kong-lab/kong.yml
```

Validate and reload:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

Wait for the new workers:

```bash
sleep 5
```

- **Verify:** run [the health check](#the-health-check).
- **Owner:** web/middleware admin (gateway team).

## Drill 12 — API key missing, wrong or blocked

Not a server fault, but you will be asked about it every day.

- **Break:** nothing — just send bad keys.
- **Observe** — no key:

```bash
curl -s -w '  -> %{http_code}\n' http://127.0.0.1:8000/api/payment/status
```

Unknown key:

```bash
curl -s -w '  -> %{http_code}\n' -H 'apikey: wrong-key' http://127.0.0.1:8000/api/payment/status
```

Blocked consumer:

```bash
curl -s -w '  -> %{http_code}\n' -H 'apikey: blocked-key-456' http://127.0.0.1:8000/api/payment/status
```

Kong access log:

```bash
sudo tail -n 3 /var/log/kong-lab/access.log
```

  - 401 for no or unknown key; 403 for a known caller outside the allowed group. Only Kong's access log has these lines; Tomcat never sees them.
- **Sample line:**

```text
{"message":"No API key found in request", ...}  -> 401
{"message":"Unauthorized", ...}  -> 401
{"message":"You cannot consume this service", ...}  -> 403
```

- **Cause:** 401 = the consumer sends no or a wrong key; 403 = an access policy decision.
- **Fix / Verify:** nothing to undo.
- **Owner:** 401 → the **API consumer**; 403 → **security / API product owner** (decides whether to grant access).

## Drill 13 — quota exceeded

Stage 4 (5 calls per minute) is installed, then 7 calls are sent.

- **Break** — install stage 4:

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/04-rate-limit.yml /etc/kong-lab/kong.yml
```

Validate and reload:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

- **Observe** — wait:

```bash
sleep 4
```

Send 7 calls:

```bash
for i in 1 2 3 4 5 6 7; do
  curl -s -o /dev/null -w '%{http_code} ' -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
done
printf '\n'
```

Show the limit headers:

```bash
curl -s -D - -o /dev/null -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status | grep -iE '^HTTP|retry-after|ratelimit'
```

  - First calls 200, then **429**; headers show the limit and when to retry.
  - If a minute boundary passes during the loop the sequence can differ; at least one 429 should still appear.
- **Sample line:**

```text
200 200 200 200 200 429 429
HTTP/1.1 429 Too Many Requests
X-RateLimit-Remaining-Minute: 0
X-RateLimit-Limit-Minute: 5
Retry-After: 19
```

- **Cause:** the consumer used its quota; Tomcat is healthy.
- **Fix** — back to stage 3:

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/03-acl.yml /etc/kong-lab/kong.yml
```

Validate and reload:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

Wait for the new workers:

```bash
sleep 5
```

- **Verify:** run [the health check](#the-health-check).
- **Owner:** the API consumer (slow down) or the API product owner (change the limit).

## Drill 14 — the log disk is full

Do not fill your real disk: a tiny 2 MB temporary disk is mounted **on top of** `/var/log/nginx`. The real logs underneath are hidden, not deleted, and come back when it is removed.

- **Break** — mount the small disk:

```bash
sudo mount -t tmpfs -o size=2M tmpfs /var/log/nginx
```

Make Nginx reopen its logs there:

```bash
sudo systemctl reload nginx
```

Wait:

```bash
sleep 2
```

Fill it:

```bash
sudo fallocate -l 2M /var/log/nginx/filler.log
```

- **Observe** — disk usage:

```bash
df -h /var/log/nginx
```

A normal request:

```bash
curl -s -o /dev/null -w '%{http_code}\n' 'http://portal.example.test:8081/health.txt?trace=drill14'
```

A missing page:

```bash
curl -s -o /dev/null -w '%{http_code}\n' 'http://portal.example.test:8081/missing?trace=drill14'
```

Were they logged?

```bash
sudo grep -c drill14 /var/log/nginx/payment-access.log
```

What uses the space:

```bash
sudo du -sh /var/log/nginx/* | sort -h
```

  - Requests are still answered (200, 404), but **no log line is written** (`grep -c` prints `0`); `df` shows 100 %. Every later investigation is blind.
  - On a real server: `df -h /var/log` first, then `sudo du -sh /var/log/* | sort -h` for the biggest folder, then the biggest files inside it.
- **Sample line:**

```text
Filesystem      Size  Used Avail Use% Mounted on
tmpfs           2.0M  2.0M     0 100% /var/log/nginx
```

- **Cause:** a full file system. On real servers: missing log rotation, a debug log left on, or a log storm.
- **Fix** (Nginx is stopped for a few seconds) — remove the filler:

```bash
sudo rm /var/log/nginx/filler.log
```

Stop Nginx:

```bash
sudo systemctl stop nginx
```

Unmount the small disk:

```bash
sudo umount /var/log/nginx
```

Start Nginx:

```bash
sudo systemctl start nginx
```

- **Verify** — normal disk again:

```bash
df -h /var/log/nginx
```

New request:

```bash
curl -s -o /dev/null -w '%{http_code}\n' 'http://portal.example.test:8081/health.txt?trace=drill14-after'
```

It is logged:

```bash
sudo tail -n 1 /var/log/nginx/payment-access.log
```

  - Lines written during the drill are lost — that is the lesson.
- **Owner:** platform/Linux admins (space and rotation), plus whoever owns the noisy log.

---

## Status code → producer → first log → owner

| Code | Who produces it in this stack | First log to read | Usual owner |
| --- | --- | --- | --- |
| 200 | Web server (static) or Tomcat, forwarded | Frontend access log | — |
| 301 | Apache/Nginx redirect rule (`/old.html`) | Frontend access log | Web/middleware admin if the target is wrong |
| 304 | Web server: client's cached copy is still current | Frontend access log | — |
| 400 | Tomcat application rejects bad input (`/slow?ms=abc`) | Tomcat access log (same 400 at the frontend) | API consumer, or developers if valid input is rejected |
| 401 | Apache/Nginx Basic auth, or Kong key-auth | Frontend access log; Apache/Nginx error log for `Password Mismatch` | User / API consumer; security if repeated |
| 403 | Apache `Require`, Nginx `deny`, filesystem permissions, Kong ACL | Frontend error log (`AH01630`, `access forbidden by rule`, `Permission denied`) | Web/middleware admin (permissions) or security (policy) |
| 404 | Web server (missing file), Tomcat (missing context or wrong WAR name), Kong (no route) | Access log of each hop: the last hop that logged 404 produced it | Content owner, deployment owner, or API consumer (wrong URL) |
| 429 | Kong rate limiting | Kong access log, `Retry-After` header | API consumer or API product owner |
| 500 | Tomcat application exception; also a web server that cannot read its own files (drill 3) | Tomcat `localhost.*.log`; frontend error log | Developers (stack trace) or web/middleware admin (server files) |
| 502 | Nginx or Kong: backend refused; Apache: backend timeout | Proxy error log (`connect() failed`, `AH01102`) | Web/middleware admin first |
| 503 | Apache: backend refused or unavailable | Apache error log (`AH00957`) | Web/middleware admin first |
| 504 | Nginx or Kong: backend too slow | Proxy error log (`upstream timed out`) | Developers (slowness) with web/middleware admin (timeouts) |

- The status code tells you **where to start**, not who is guilty. The evidence line decides the owner.

## Finish

- Run [the health check](#the-health-check) one last time, then return Kong to stage 4 as Lab 5 left it.

Install stage 4:

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/04-rate-limit.yml /etc/kong-lab/kong.yml
```

Validate and reload:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

- Record one incident per drill in your [evidence worksheet](06-student-evidence.md). Model answers: [knowledge check answers](09-knowledge-check-answers.md).
