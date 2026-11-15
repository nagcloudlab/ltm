# Knowledge check — model answers

- Use this page **after** writing your own answers to the questions in the [evidence worksheet](06-student-evidence.md).
- A good answer names the evidence, not only the idea. Short, plain answers are enough.

## Short knowledge check

**1. Why can `systemctl is-active` succeed when curl fails?**

- `is-active` only proves a process runs — not that it listens on the expected address/port, or that the URL exists.
- Lab examples: Tomcat on 8090 instead of 8080; WAR deployed as `payment-1.2` (404); Apache proxy pointing at the wrong port (503); `portal.example.test` not resolving.
- Prove all three levels: process (`systemctl`, `pgrep`), listener (`ss -lntp`), answer (`curl`).

**2. Why do both web servers return the same static page but have different access logs?**

- Both read `/var/www/payment-portal`, but each is a separate program with its own config, port and logs.
- Apache logs to `/var/log/apache2/payment-access.log`, Nginx to `/var/log/nginx/payment-access.log`. Only the server that received the request logs it.

**3. What changes in the URL when a WAR is named `orders.war`?**

- The WAR name is the context path: the app moves to `/orders/...`, e.g. `http://127.0.0.1:8080/orders/status`.
- Proxies and Kong still send `/payment/...` → 404 until the name or routes change.

**4. Why does `proxy_pass http://127.0.0.1:8080;` preserve `/payment/`?**

- No path after the port → Nginx forwards the path unchanged: `/payment/status` stays `/payment/status`.
- With a path (e.g. `http://127.0.0.1:8080/`) Nginx replaces the `location` prefix: `/payment/status` → `/status`, the wrong Tomcat context.

**5. Why is a proxy 504 different from a refused TCP connection?**

- Refused: nothing listens on the backend port; fails at once. Nginx and Kong 502, Apache 503. Error log: `Connection refused`.
- 504: connected and sent the request, but no answer before the proxy timeout (10 seconds here). Error log: `upstream timed out`. Tomcat runs and may even log 200 later.
- Different owners: stopped service (admin) vs slow application (developers).

**6. Why must other external proxy routes be restricted if Kong should guard every API call?**

- Kong checks keys, ACLs and quotas only on port 8000.
- Apache and Nginx `/payment/` go straight to Tomcat with no checks — a bypass. Remove or restrict them (Lab 5 lockdown).

**7. Why can rate limiting hide a backend failure during a test?**

- Over quota, Kong answers 429 itself and never contacts Tomcat.
- With Tomcat down you still see 429, not 502. So backend faults are tested with stage 3 (no rate limit).

**8. What evidence would you give developers for a reproducible application 500?**

- The exact request (method, URL, needed headers) and the command that reproduces it.
- Time **with time zone**, and the status at each hop (proxy and Tomcat access logs both show 500).
- Stack trace from `/opt/tomcat/logs/localhost.YYYY-MM-DD.log`: the exception line and first application line, e.g. `lab.PaymentServlet.doGet(PaymentServlet.java:15)`.
- Proof the platform is healthy: other URLs (`/payment/status`) answer 200.

## "Explain to a partner" prompts

**Apache — Host header vs filesystem permissions**

- `Host` header (name in the URL) picks **which site** answers, matched against `ServerName`.
- Filesystem permissions decide whether `www-data` may **read that site's files**: every folder needs `x`, the file needs `r`.
- Wrong name → wrong or default site. Missing permission → 403, `Permission denied` in the error log (check with `namei -l`).

**Nginx — same content, independent web-server config**

- Same folder as Apache, but its own port (8081), `server` block, rules, password file copy and logs.
- Breaking Nginx config (missing semicolon, wrong `root`) does not affect Apache, and vice versa.

**Tomcat — Tomcat configuration vs app packaging**

- Admin owns configuration: `server.xml` (address, port), systemd unit (`JAVA_HOME`, memory, user), file permissions, WAR file name.
- Developers own packaging: what is inside the WAR — `WEB-INF/web.xml`, classes, libraries.
- Missing class (`payment-broken.war`) = packaging fault; broken `server.xml` = configuration fault.

**Reverse proxy — which hop failed and why**

- Test the backend directly (`curl http://127.0.0.1:8080/payment/status`). Works → fault is between proxy and backend; fails → backend.
- Compare proxy and Tomcat access logs: same code in both = Tomcat produced it; only at the proxy = the proxy produced it.
- Proxy error log names the reason: `Connection refused` (backend down / wrong port) or `timed out` (backend slow).

**Gateway — authentication vs authorization vs quota**

| Check | Question | Failure |
| --- | --- | --- |
| Authentication | Who are you? | No or unknown key → 401 |
| Authorization | Are you allowed? | Known key, consumer not in allowed ACL group → 403 |
| Quota | How much may you use? | Over 5 requests per minute → 429 |

- All three are decided in Kong; Tomcat never sees these requests.
