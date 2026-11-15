# Module 12 notes: Configuration and performance

60 slides (`order-m12.txt`), generator `gen2/m12.py` (contact-sheet helper `gen2/m12sheet.py`).

## Versions tested (container d2-m12, Ubuntu 24.04.5, arm64)
- Tomcat 10.1.61 tarball in /opt/tomcat, OpenJDK 21.0.13 (openjdk-21-jdk-headless, needed for jcmd)
- Second Tomcat: CATALINA_BASE /opt/tomcat2, HTTP 8082, shutdown 8006, unit `tomcat2`
- Nginx 1.24.0, Apache 2.4.58, Kong 3.9.1 (OSS deb, DB-less), PostgreSQL 16.15 + libpostgresql-jdbc-java 42.7.2
- payment.war imitation: plain servlets (JSP compile was far too slow in the container). Extra lab pages used by this module: `/payment/node` (prints port), `/payment/whoami` (remoteAddr, XFF, proto), `/payment/session` (session id, visits, timeout), `/payment/db?hold=ms`, `/payment/leak`. The lab bundle's payment.war must contain these.

## Verified for real (output on slides is captured)
- catalina.out deploy/redeploy/undeploy lines; manager text API list/undeploy/deploy/reload; parallel deployment payment##002.war
- Nginx upstream with **`payment_app`** name and no Host header → Tomcat 10.1 returns **400** ("The host [payment_app] is not valid", "The character [_] is never valid in a domain name"). Day 1's m7-lb-nginx used that upstream name; fixed with `proxy_set_header Host $host`.
- Round robin without `zone` gave all requests to 8080 (per-worker counters, worker_processes auto); with `zone payment_app 64k;` it alternates. Weight 3:1, least_conn, ip_hash (first 3 octets), session loss under RR, `down` flag.
- Node down: client sees 200, access log `ua=127.0.0.1:8082, 127.0.0.1:8080 us=502, 200`; both down: 502 + "no live upstreams".
- RemoteIpValve (protocolHeader="x-forwarded-proto"); AccessLogValve needs `requestAttributesEnabled="true"` to log the real client.
- Tomcat 10.1 access log `%D` = **microseconds**, `%I` thread name; `%t` stamps appeared to be response end time.
- Thread dump via jcmd and kill -3; maxThreads=4 experiment; `ss` Recv-Q 98 on waiting connections; LISTEN Send-Q 100 = acceptCount.
- DBCP2 exhaustion text: "Cannot get a connection, pool error Timeout waiting for idle object, maxWaitDuration=PT1.884852125S"; DB down: "PSQLException: Connection to 127.0.0.1:5432 refused…"; leak + logAbandoned "Pooled object created … has not been returned to the pool" pointing to LeakServlet.
- Session timeout change via watched WEB-INF/web.xml (Reloading Context lines; session expiry after 75 s).
- 499 (curl --max-time 3), Nginx 504 read timeout, Nginx 504 connect timeout via iptables DROP ("while connecting to upstream"), Nginx 408 (client_header_timeout 5s), Kong 504 JSON body "The upstream server is timing out", Kong default service timeouts 60000/60000/60000 retries 5.
- **Kong retries 5 on a timed-out GET → 6 executions in Tomcat**, client waits 6×; `retries: 0` → one.
- **Nginx proxy_next_upstream default retries a read timeout on the other node** (504 after 20 s with 10 s timeout); fixed with `proxy_next_upstream error;`.
- **Apache ProxyTimeout expiry gives 502**, not 504: "(70007)The timeout specified has expired … AH01102".
- Wrong chain (Kong 5 s, Nginx 20 s): Kong 504, Nginx 499, Tomcat 200 after 8 s.
- Full trace Kong→Nginx→Tomcat with timings (machine was loaded; numbers are real but noisy).

## Not run / from documentation only
- EAR deployment (no WebLogic/WebSphere/JBoss); EAR structure from Jakarta EE.
- pgjdbc connectTimeout 10 s / socketTimeout 0 (driver docs). Nginx 60 s defaults, curl defaults, Apache compiled default Timeout 60 (Ubuntu conf 300 was grep'd).
- Tomcat connector defaults (200/10/8192/100/60000) read from the bundled 10.1 docs, not measured.

## State left at the end of the lab (Module 13 should assume)
- Kong service `payment` url **http://127.0.0.1:8081/payment** (Kong → Nginx → two Tomcats), connect_timeout 5000, read/write_timeout 25000, retries 0; key-auth unchanged (rate limit in our test was raised to 100/min to avoid 429s during tests; the lab handout should say so).
- Nginx :8081 `upstream payment_app { zone payment_app 64k; server 127.0.0.1:8080; server 127.0.0.1:8082; }`, four proxy_set_header lines, proxy_connect_timeout 5s, proxy_read_timeout 20s, proxy_next_upstream error, log_format `timing` in /etc/nginx/conf.d/timing.conf.
- Tomcat 8080 and 8082: RemoteIpValve, AccessLogValve pattern `%h %l %u %t "%r" %s %b %D %I` with requestAttributesEnabled="true"; maxThreads default.
- PostgreSQL :5432, db paydb, user payapp/Pay-123, table payments (42 rows); pool in /opt/tomcat/conf/Catalina/localhost/payment.xml (maxTotal 3, maxWaitMillis 2000, removeAbandoned settings). Only the 8080 node has the pool in our test.
- Apache payment.conf: `ProxyTimeout 5` and LogFormat with %D were test values; the lab should set ProxyTimeout to fit the chain (e.g. 20).
- New status codes introduced: **499**, **408**. 400 appears in the Host trap slide.
