# Module 13 — Integrated troubleshooting: build notes

Generator: `gen2/m13.py` (runs `m13a.py` workflow/hops/request IDs, `m13b.py` time/formats/status codes/202,
`m13c.py` incidents/escalation/3 cases/report/lab/QC; helpers in `m13common.py`). Writes `order-m13.txt`.
48 slides. Raw captures: `$S/m13cap/*.txt`. Lab files used in the container (lab-bundle candidates): `lab/`.

## Versions tested (container `d2-m13`, mw-ubuntu-test:24.04, arm64, TZ set to Asia/Kolkata)
- Tomcat **10.1.61** tarball in /opt/tomcat, systemd `tomcat`, OpenJDK 21.0.13 (slides show students' amd64 paths only where needed).
- Nginx 1.24.0 (Ubuntu), Apache 2.4.58 (Ubuntu), RabbitMQ 3.12.1 (+ management, rabbitmqadmin), python3-pika 1.2.0, chrony.
- Kong: **Kong Enterprise 3.11.0.14** package (`kong-enterprise-edition` from packages.konghq.com gateway-311, noble, arm64) running
  without a licence (free mode). Headers therefore show `kong/3.11.0.14-enterprise-edition`; students on OSS Kong 3.x will see `kong/3.x.y`.
- Kafka not installed here; the Kafka lag command is only referenced (Module 10 owns real output).

## Lab setup assumed by Module 13 (lead / lab bundle must provide)
- Kong service `payment` url changed to `http://127.0.0.1:8081/payment` (Kong → Nginx → Tomcat), `read_timeout: 5000`,
  plugins key-auth + **correlation-id** (`header_name: X-Request-ID`, `generator: uuid`, `echo_downstream: true`).
  Rate-limiting is left out of the Module 13 kong.yml (bursts of 6+ requests). File: `lab/kong.yml`.
- kong.conf additions: custom `nginx_http_log_format = trace '…rid=$http_x_request_id kong_request_id=$kong_request_id'`,
  `proxy_access_log = logs/access.log trace`, `ssl_cert`/`ssl_cert_key` for Case 1 (`lab/kong.conf.additions`).
- Nginx `/etc/nginx/conf.d/payment-api.conf` on :8081 with `map $http_x_request_id $reqid`, `log_format trace … rt= urt= rid=`,
  `proxy_set_header X-Request-ID $reqid`, `proxy_read_timeout 10s`, log `/var/log/nginx/payment-access.log`.
  NOTE: I removed `sites-enabled/default` because it held port 80 against Apache; check this doesn't clash with Module 4/12 configs.
- Tomcat AccessLogValve pattern `%h %l %u %t "%r" %s %b %D %{X-Request-ID}i`.
- **Payment app needs `POST /payment/transfer`** returning **202** `{"status":"ACCEPTED","transferId":"TX…"}`, publishing
  PaymentCompleted to exchange `payments` (topic) with routing key `payment.completed`, copying X-Request-ID into message header
  `x-request-id` and logging `transfer TXnnn published PaymentCompleted requestId=… broker=200` (I imitated it with JSP + the
  management HTTP API; `lab/payment/`). If Module 9's app differs, the Case 3 / request-ID slides' log lines differ.
- notification-service: `/opt/notification.py` (pika consumer of queue `sms`, systemd `notification`, log
  `/var/log/notification/notification.log`), flag `BUG = True` reads field `mobile` instead of `phone` → KeyError → reject(requeue=false) → sms.dlq.
- Case 1 PKI: root "PayBank Lab Root CA", intermediate "PayBank Lab Issuing CA 1" (names aligned with Module 11), gateway cert
  `api.example.com` served by **Kong on 8443** (Kong's own TLS; Nginx HTTPS stays on 443 per Module 11). Expired intermediate
  NotAfter 14 Nov 2026 00:00 GMT; renewed one to 2029. `/etc/hosts`: `127.0.0.1 api.example.com`. Script `lab/pki.sh`,
  Java client `Call.java`. Lab bundle needs `~/lab/m13/` with the expired chain + root (`paybank-root.crt`).
- IIS sample `~/lab/iis/u_ex261115.log` with custom field X-Request-ID: written by me (`lab/u_ex261115.log`), **not captured**.

## Verified for real (captured in the container)
- Response headers through Kong→Nginx→Tomcat (Server nginx, Via kong, X-Kong-Upstream/Proxy-Latency, X-Kong-Request-Id, X-Request-ID);
  Tomcat 10.1 sends no Server header.
- Error bodies: Kong 401 "No API key found in request", 404 "no Route matched with those values", 502 "An invalid response was received
  from the upstream server", 504 "The upstream server is timing out" (all JSON with request_id, Server: kong); Nginx 502/504 HTML passed
  through Kong (Server nginx + Via kong); Tomcat 404/500 pages; Apache 503 page for payment.example.com vhost; matching error-log lines.
- correlation-id schema defaults (Kong-Request-ID, uuid#counter, false); Kong keeps a client-supplied X-Request-ID; grep -r for
  `trainee01-001` gives exactly 5 lines (Kong, Nginx, Tomcat access, Tomcat app, notification).
- **Tomcat 10.1 %D is microseconds** (slow?ms=70000 → 71452857). Tomcat %D excludes time queued waiting for a thread.
- Nginx $request_id 32-hex when no incoming header; Nginx→Tomcat is HTTP/1.0.
- Time: date conversions, epoch, ms epoch, timedatectl, chronyc tracking/sources, Date-header comparison.
- awk/grep recipes on the real logs (outputs shown on slides).
- Case 2 (maxThreads=4 + four slow?ms=70000): Kong 504 after 30 s with **6 upstream attempts** (Kong service `retries` default 5) for GET;
  POSTs not retried; Nginx 499 ×6 same rid; direct curl 000 after 5 s; ss Recv-Q 642; kill -3 thread dump (4 exec threads in slow_jsp);
  Tomcat logs the 6 copies later with tiny %D.
- Accidental but real: Kong 504 / Nginx 499 / Tomcat 202 + published for the same transfer (slide m13-504-done) on the loaded host.
- Case 3: 202s, sms 0 msgs/1 consumer, sms.dlq 6, consumer ERROR lines, management-API get with x-death (reason rejected, epoch),
  fix → "SMS sent".
- Case 1: curl (60) certificate has expired, Java 21 PKIX "validity check failed", s_client depth=1 verify error 10, fix → OK, -checkend.

## Not verified / constructed
- IIS custom-field config window and IIS log lines (no IIS on Linux); IIS 502.3 for ARR timeout and the Microsoft-IIS/10.0 header are from Day 1 knowledge.
- Severity levels, timeline (times after 11:35 are an example pace; lab incident lasted ~70 s), comms template, escalation table: process content.
- Many outputs were captured on a heavily loaded Docker host (load avg >200), so some durations are large (status 2 s, transfer 2.6 s); notes say so.
- JetBrains Mono ligatures display `>=`, `<=`, `->` as ≥ ≤ → in code blocks (same as other modules).

## Facts other modules must stay consistent with
- Day 2 status-code table lives in m13-codes-1 / m13-codes-2 (200, 202, 206/304, 301/302, 401, 403, 404, 429, 499, 500, 502, 503, 504, IIS 502.3, TLS/no-code).
- Kong 3.x: X-Kong-Response-Latency only on Kong-generated answers; retries default 5; error JSON always has request_id.
