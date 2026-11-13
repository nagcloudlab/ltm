#!/usr/bin/env bash
# setup-lab.sh -- builds a simulated "PayBank" middleware server under ~/lab/srv
# Safe: writes only inside your home folder. Run again any time to reset.
set -euo pipefail

L="$HOME/lab/srv"
rm -rf "$L"
mkdir -p "$L"/{etc/apache2/sites-available,etc/payment,var/log/apache2,var/log/payment/archived,opt/tomcat/logs,opt/tomcat/webapps,run,scripts,backup}

# ---------- Apache access log (combined + response time in microseconds as field 11) ----------
cat > "$L/var/log/apache2/access.log" <<'LOG'
10.0.0.21 - - [24/Aug/2026:09:01:15 +0530] "GET /portal/ HTTP/1.1" 200 5120 "-" "Mozilla/5.0" 41250
10.0.0.22 - - [24/Aug/2026:09:01:30 +0530] "GET /portal/login HTTP/1.1" 200 2210 "-" "Mozilla/5.0" 38120
10.0.0.21 - - [24/Aug/2026:09:02:30 +0530] "POST /payment/transfer HTTP/1.1" 500 128 "-" "Mozilla/5.0" 2010
10.0.0.45 - - [24/Aug/2026:09:03:45 +0530] "GET /portal/static/logo.png HTTP/1.1" 200 15234 "-" "Mozilla/5.0" 1200
10.0.0.21 - - [24/Aug/2026:09:04:00 +0530] "GET /payment/history?acct=1234 HTTP/1.1" 200 8921 "-" "Mozilla/5.0" 2501000
10.0.0.33 - - [24/Aug/2026:09:05:12 +0530] "POST /payment/transfer HTTP/1.1" 504 89 "-" "okhttp/4.12" 30001000
10.0.0.21 - - [24/Aug/2026:09:06:30 +0530] "GET /payment/balance?acct=1234 HTTP/1.1" 200 342 "-" "okhttp/4.12" 52000
10.0.0.88 - - [24/Aug/2026:09:07:15 +0530] "GET /payment/balance?acct=8812 HTTP/1.1" 200 342 "-" "okhttp/4.12" 41000
10.0.0.21 - - [24/Aug/2026:09:07:45 +0530] "POST /payment/transfer HTTP/1.1" 500 128 "-" "Mozilla/5.0" 2000
10.0.0.55 - - [24/Aug/2026:09:08:00 +0530] "GET /portal/old.html HTTP/1.1" 301 230 "-" "Mozilla/5.0" 900
10.0.0.77 - - [24/Aug/2026:09:08:30 +0530] "GET /portal/sale.html HTTP/1.1" 404 196 "-" "Mozilla/5.0" 800
10.0.0.108 - - [24/Aug/2026:09:09:15 +0530] "GET /payment/history?acct=1080 HTTP/1.1" 200 12043 "-" "Mozilla/5.0" 3201000
10.0.0.21 - - [24/Aug/2026:09:10:30 +0530] "POST /payment/transfer HTTP/1.1" 400 67 "-" "okhttp/4.12" 15000
10.0.0.21 - - [24/Aug/2026:09:11:00 +0530] "GET /payment/balance?acct=1234 HTTP/1.1" 200 342 "-" "okhttp/4.12" 48000
10.0.0.33 - - [24/Aug/2026:09:11:45 +0530] "GET /admin/ HTTP/1.1" 401 381 "-" "curl/8.5.0" 700
10.0.0.21 - - [24/Aug/2026:09:12:00 +0530] "POST /payment/transfer HTTP/1.1" 500 128 "-" "Mozilla/5.0" 2000
10.0.0.21 - - [24/Aug/2026:09:12:30 +0530] "GET /payment/history?acct=1234 HTTP/1.1" 200 8921 "-" "Mozilla/5.0" 4102000
10.0.0.21 - - [24/Aug/2026:09:13:15 +0530] "POST /payment/transfer HTTP/1.1" 503 45 "-" "okhttp/4.12" 1000
10.0.0.22 - - [24/Aug/2026:09:13:16 +0530] "GET /payment/balance?acct=2200 HTTP/1.1" 503 45 "-" "okhttp/4.12" 1000
10.0.0.45 - - [24/Aug/2026:09:13:17 +0530] "POST /payment/transfer HTTP/1.1" 503 45 "-" "Mozilla/5.0" 1000
10.0.0.88 - - [24/Aug/2026:09:13:18 +0530] "GET /payment/balance?acct=8812 HTTP/1.1" 503 45 "-" "okhttp/4.12" 1000
10.0.0.55 - - [24/Aug/2026:09:13:20 +0530] "POST /payment/transfer HTTP/1.1" 503 45 "-" "Mozilla/5.0" 1000
10.0.0.21 - - [24/Aug/2026:09:14:00 +0530] "GET /payment/balance?acct=1234 HTTP/1.1" 503 45 "-" "okhttp/4.12" 1000
10.0.0.33 - - [24/Aug/2026:09:14:30 +0530] "GET /payment/status HTTP/1.1" 503 22 "-" "curl/8.5.0" 1000
10.0.0.203 - - [24/Aug/2026:09:14:40 +0530] "GET /wp-login.php HTTP/1.1" 404 196 "-" "python-requests/2.31" 600
10.0.0.203 - - [24/Aug/2026:09:14:41 +0530] "GET /.env HTTP/1.1" 403 199 "-" "python-requests/2.31" 500
10.0.0.21 - - [24/Aug/2026:09:15:00 +0530] "GET /payment/balance?acct=1234 HTTP/1.1" 200 342 "-" "okhttp/4.12" 55000
10.0.0.33 - - [24/Aug/2026:09:15:30 +0530] "POST /payment/transfer HTTP/1.1" 500 128 "-" "Mozilla/5.0" 2000
10.0.0.21 - - [24/Aug/2026:09:16:15 +0530] "GET /payment/status HTTP/1.1" 503 22 "-" "curl/8.5.0" 1000
10.0.0.21 - - [24/Aug/2026:09:16:30 +0530] "GET /payment/status HTTP/1.1" 503 22 "-" "curl/8.5.0" 1000
LOG

# ---------- Apache error log ----------
cat > "$L/var/log/apache2/error.log" <<'LOG'
[Mon Aug 24 09:00:00.101234 2026] [mpm_event:notice] [pid 1201:tid 1201] AH00489: Apache/2.4.58 (Ubuntu) configured -- resuming normal operations
[Mon Aug 24 09:05:12.004411 2026] [proxy_http:error] [pid 1203:tid 1220] (70007)The timeout specified has expired: [client 10.0.0.33:51344] AH01102: error reading status line from remote server 127.0.0.1:8080
[Mon Aug 24 09:08:30.551200 2026] [core:info] [pid 1204:tid 1231] [client 10.0.0.77:50120] AH00128: File does not exist: /var/www/portal/sale.html
[Mon Aug 24 09:11:45.330021 2026] [auth_basic:error] [pid 1203:tid 1221] [client 10.0.0.33:52011] AH01618: user admin not found: /admin/
[Mon Aug 24 09:13:15.002210 2026] [proxy:error] [pid 1204:tid 1232] (111)Connection refused: AH00957: http: attempt to connect to 127.0.0.1:8080 (localhost:8080) failed
[Mon Aug 24 09:13:15.002300 2026] [proxy_http:error] [pid 1204:tid 1232] [client 10.0.0.21:51990] AH01114: HTTP: failed to make connection to backend: localhost
[Mon Aug 24 09:14:41.120001 2026] [authz_core:error] [pid 1203:tid 1222] [client 10.0.0.203:40112] AH01630: client denied by server configuration: /var/www/portal/.env
LOG

# ---------- App server (Tomcat-style) log with the incident timeline ----------
cat > "$L/opt/tomcat/logs/catalina.out" <<'LOG'
2026-08-24 09:00:01 INFO  [main] Server startup in 4120 ms, port 8080
2026-08-24 09:00:05 INFO  [payment-service] Deployed /payment, 3 servlets
2026-08-24 09:00:08 INFO  [portal-service] Deployed /portal
2026-08-24 09:01:15 INFO  [payment-service] Balance read acct=1234 ok
2026-08-24 09:02:30 ERROR [payment-service] Transfer failed: NullPointerException at TransferServlet.java:88
2026-08-24 09:04:00 WARN  [payment-service] Slow query: SELECT * FROM txn WHERE acct=1234 (query_time=2500ms)
2026-08-24 09:05:12 ERROR [payment-service] Transfer failed: Read timed out calling core-banking:9443
2026-08-24 09:07:45 ERROR [payment-service] Transfer failed: NullPointerException at TransferServlet.java:88
2026-08-24 09:09:15 WARN  [payment-service] Slow query: SELECT * FROM txn WHERE acct=1080 (query_time=3200ms)
2026-08-24 09:10:30 ERROR [payment-service] Transfer rejected: invalid IFSC code
2026-08-24 09:12:00 ERROR [payment-service] Transfer failed: NullPointerException at TransferServlet.java:88
2026-08-24 09:12:30 WARN  [payment-service] Slow query: SELECT * FROM txn WHERE acct=1234 (query_time=4100ms)
2026-08-24 09:13:14 FATAL [db-pool] Connection pool exhausted: maxTotal=20 active=20 waiting=31
2026-08-24 09:13:14 ERROR [payment-service] Cannot get JDBC connection: pool exhausted
2026-08-24 09:13:14 FATAL [main] Out of memory: Java heap space; JVM exiting
2026-08-24 09:14:30 FATAL [startup] Auto-restart failed: lock file exists /run/payment.lock
2026-08-24 09:15:00 INFO  [portal-service] Health check: OK
2026-08-24 09:16:15 ERROR [payment-service] Health check: FAIL (not running)
LOG

# ---------- Configs: production vs staging ----------
cat > "$L/etc/payment/app-prod.properties" <<'CFG'
## payment-service · PRODUCTION
app.name=payment-service
app.env=production
server.port=8080
db.url=jdbc:postgresql://prod-db-01.bank.internal:5432/payments
db.username=pay_app
db.pool.maxTotal=20
db.pool.maxWaitMillis=5000
corebanking.url=https://core-banking.bank.internal:9443
corebanking.timeoutMillis=30000
jvm.heap.max=512m
log.level=INFO
CFG
cat > "$L/etc/payment/app-staging.properties" <<'CFG'
## payment-service · STAGING
app.name=payment-service
app.env=staging
server.port=8080
db.url=jdbc:postgresql://stg-db-01.bank.internal:5432/payments
db.username=pay_app
db.pool.maxTotal=100
db.pool.maxWaitMillis=5000
corebanking.url=https://core-banking-stg.bank.internal:9443
corebanking.timeoutMillis=10000
jvm.heap.max=2048m
log.level=DEBUG
CFG

# ---------- Apache site file ----------
cat > "$L/etc/apache2/sites-available/portal.conf" <<'CFG'
<VirtualHost *:80>
    ServerName portal.example.com
    DocumentRoot /var/www/portal
    ProxyPass        /payment http://localhost:8080/payment
    ProxyPassReverse /payment http://localhost:8080/payment
    ErrorLog ${APACHE_LOG_DIR}/portal-error.log
    CustomLog ${APACHE_LOG_DIR}/portal-access.log combined
</VirtualHost>
CFG
cp "$L/etc/apache2/sites-available/portal.conf" "$L/backup/portal.conf.bak"
# someone changed production without telling anyone (find it with diff)
awk '{ sub("/var/www/portal$", "/var/www/portal2"); print }' "$L/backup/portal.conf.bak" > "$L/etc/apache2/sites-available/portal.conf"

# ---------- The lock file that blocks the restart ----------
echo "pid=4123 started=2026-08-24T09:13:14" > "$L/run/payment.lock"

# ---------- Big files that fill the disk ----------
# fallocate really uses the space, so du and df see it (truncate would not)
big() { fallocate -l "$1" "$2" 2>/dev/null || truncate -s "$1" "$2"; }
big 120M "$L/opt/tomcat/logs/catalina.2026-08-23.log"
big 60M  "$L/opt/tomcat/logs/heapdump-4123.hprof"
big 12M  "$L/var/log/apache2/access.log.1"
big 2M   "$L/var/log/payment/gc.log"
for d in 15 16 17 18 19 20; do echo "old log $d" | gzip > "$L/var/log/payment/archived/app.log.2026-08-$d.gz"; done
touch "$L/opt/tomcat/webapps/payment.war" "$L/opt/tomcat/webapps/portal.war"

# ---------- A runaway CPU script (for the kill exercise) ----------
cat > "$L/scripts/rebuild_index.sh" <<'SH'
#!/usr/bin/env bash
# pretends to rebuild a search index; really just burns CPU
while true; do :; done
SH
chmod 755 "$L/scripts/rebuild_index.sh"

echo "Lab ready in $L"
find "$L" -type f | sort | sed "s#$HOME#~#"
