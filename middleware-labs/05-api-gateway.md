# Lab 5 — Publish and protect the payment API with Kong

- **Needs:** [Lab 4](04-reverse-proxy.md) healthy; repository cloned on this laptop; internet access to install the Kong package
- **You build:** the same Tomcat app exposed through a gateway with API keys, authorization and rate limiting

```text
curl -> Kong :8000 -> Tomcat 127.0.0.1:8080/payment/
        Admin API 127.0.0.1:8001 (local administrators only)
```

- Kong runs as a native Ubuntu service in DB-less mode (no database, no application build).
- Four prepared config files add, in turn: routing, API keys, authorization, rate limiting.

## 1. Verify the backend and install Kong

Call Tomcat directly:

```bash
curl -s http://127.0.0.1:8080/payment/status
```

Call through Apache:

```bash
curl -s http://portal.example.test/payment/status
```

Call through Nginx:

```bash
curl -s http://portal.example.test:8081/payment/status
```

Check that the proxy port is unused:

```bash
sudo ss -lntp 'sport = :8000'
```

Check that the Admin API port is unused:

```bash
sudo ss -lntp 'sport = :8001'
```

- **Expected:** three healthy answers; ports 8000 and 8001 unused.
- This lab pins **Kong OSS 3.9.1** (native Ubuntu 24.04 packages, AMD64 and ARM64, Kong's signed repository). It is a historical classroom version — keep the supplied local-only listener settings.

Show the Ubuntu codename:

```bash
lsb_release -sc
```

Show the architecture:

```bash
dpkg --print-architecture
```

- **Expected:** `noble`, and `amd64` or `arm64`.

Refresh the package lists:

```bash
sudo apt update
```

Install the repository tools:

```bash
sudo apt install -y curl ca-certificates gnupg lsb-release
```

Download Kong's signing key:

```bash
curl -fsSL https://packages.konghq.com/public/gateway-39/gpg.key -o /tmp/kong-gateway-39.key
```

Convert it into a keyring:

```bash
sudo gpg --dearmor --yes -o /usr/share/keyrings/kong-gateway-39-archive-keyring.gpg /tmp/kong-gateway-39.key
```

Download the repository definition:

```bash
curl -fsSL 'https://packages.konghq.com/public/gateway-39/config.deb.txt?distro=ubuntu&codename=noble' -o /tmp/kong-gateway-39.list
```

Install it:

```bash
sudo install -m 644 /tmp/kong-gateway-39.list /etc/apt/sources.list.d/kong-gateway-39.list
```

Refresh the package lists again:

```bash
sudo apt update
```

See the available Kong versions:

```bash
apt-cache policy kong
```

Install the pinned version:

```bash
sudo apt install -y kong=3.9.1
```

Stop upgrades from replacing it:

```bash
sudo apt-mark hold kong
```

Check the version:

```bash
kong version
```

Check the executable path:

```bash
command -v kong
```

- **Expected:** `3.9.1` and `/usr/local/bin/kong`.
- `apt-cache policy` shows newer 3.9.x builds as candidate; `apt-mark hold` stops `apt upgrade` replacing the pin.
- **If the OS, version or path differs:** fix that first. Do not install a different major/minor version.

## 2. Install and inspect the prepared configuration

Create the `kong-lab` service account:

```bash
sudo useradd --system --user-group --home-dir /var/lib/kong-lab --shell /usr/sbin/nologin kong-lab
```

Create the config directory:

```bash
sudo install -d -o root -g kong-lab -m 750 /etc/kong-lab
```

Create the runtime and log directories:

```bash
sudo install -d -o kong-lab -g kong-lab -m 750 /var/lib/kong-lab /var/log/kong-lab
```

Install `kong.conf`:

```bash
sudo install -o root -g kong-lab -m 640 ~/ltm/middleware-labs/project-files/config/kong.conf /etc/kong-lab/kong.conf
```

Install stage 1 (open route) as `kong.yml`:

```bash
sudo install -o root -g kong-lab -m 640 ~/ltm/middleware-labs/project-files/kong/01-open.yml /etc/kong-lab/kong.yml
```

Read `kong.conf`:

```bash
sudo cat /etc/kong-lab/kong.conf
```

Read `kong.yml`:

```bash
sudo cat /etc/kong-lab/kong.yml
```

Validate the configuration:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf
```

- **Expected:** `parse successful` (exit 0).
- A `[warn] ulimit is currently set to "1024"` line is harmless; the systemd unit raises the limit.
- **If the account already exists:** inspect it with `getent passwd kong-lab` before reusing it.

| File or directory | Purpose |
| --- | --- |
| `/etc/kong-lab/kong.conf` | Listeners, DB-less mode, logs and runtime prefix |
| `/etc/kong-lab/kong.yml` | Services, routes, consumers and plugins |
| `/var/lib/kong-lab/` | Writable runtime files and PID |
| `/var/log/kong-lab/` | Gateway access/error logs |

| Kong term | Value in this project |
| --- | --- |
| Service | `payment`: backend `http://127.0.0.1:8080/payment` |
| Route | `payment-route`: public prefix `/api/payment` |
| Consumer | A named API caller |
| Plugin | A check added to the service |

- With `strip_path: true`, `/api/payment/status` becomes backend `/payment/status`.

## 3. Start Kong as a systemd service

Read the unit file:

```bash
cat ~/ltm/middleware-labs/project-files/config/payment-kong.service
```

Install it:

```bash
sudo cp ~/ltm/middleware-labs/project-files/config/payment-kong.service /etc/systemd/system/payment-kong.service
```

Reload systemd:

```bash
sudo systemctl daemon-reload
```

Enable and start Kong:

```bash
sudo systemctl enable --now payment-kong
```

Check the status:

```bash
systemctl status payment-kong --no-pager
```

Read the journal:

```bash
sudo journalctl -u payment-kong -n 30 --no-pager
```

Check Kong's health:

```bash
sudo -u kong-lab kong health -p /var/lib/kong-lab
```

Check the proxy listener:

```bash
sudo ss -lntp 'sport = :8000'
```

Check the Admin API listener:

```bash
sudo ss -lntp 'sport = :8001'
```

Call the Admin API:

```bash
curl -i http://127.0.0.1:8001/status
```

Call the status page through Kong:

```bash
curl -i http://127.0.0.1:8000/api/payment/status
```

Call the balance page through Kong:

```bash
curl -i http://127.0.0.1:8000/api/payment/balance
```

- **Expected:** service active, Kong healthy, loopback listeners on 8000/8001, 200 responses.
- Kong and Tomcat both run on this laptop, so Kong reaches Tomcat's loopback address.
- **If startup fails:** read the journal and `/var/log/kong-lab/error.log`. Do not run a manual `kong start` alongside systemd.

## 4. Observe gateway routing and logs

**Terminal A** — follow Kong's logs (Ctrl+C when done):

```bash
sudo tail -f /var/log/kong-lab/access.log /var/log/kong-lab/error.log
```

**Terminal B** — call a known route with a marker:

```bash
curl -i 'http://127.0.0.1:8000/api/payment/status?trace=kong-open'
```

Call an unknown route:

```bash
curl -i http://127.0.0.1:8000/api/unknown
```

Wait for Tomcat's access log to flush:

```bash
sleep 10
```

Find the marked request in Tomcat's log:

```bash
sudo sh -c 'grep "kong-open" /opt/tomcat/logs/localhost_access_log.*.txt'
```

- **Expected:** known route 200 (reaches Tomcat); unknown route 404 from Kong with `"message":"no Route matched with those values"` (never reaches Tomcat).
- Request logs: `/var/log/kong-lab/access.log`. Upstream errors: `/var/log/kong-lab/error.log`. Startup failures: the journal.

## 5. Add API-key authentication

- Pattern for every stage change: save, install, parse, reload only if parse succeeds.

Save the current file:

```bash
sudo cp /etc/kong-lab/kong.yml ~/lab/backups/kong-open.yml
```

Install stage 2 (key-auth):

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/02-key-auth.yml /etc/kong-lab/kong.yml
```

Validate, then reload:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

Wait for the new workers (a reload takes a second or two to apply):

```bash
sleep 5
```

No key:

```bash
curl -i http://127.0.0.1:8000/api/payment/status
```

Wrong key:

```bash
curl -i -H 'apikey: wrong-key' http://127.0.0.1:8000/api/payment/status
```

Demo key:

```bash
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

Blocked partner key:

```bash
curl -i -H 'apikey: blocked-key-456' http://127.0.0.1:8000/api/payment/status
```

- **Expected:** `401` (`"message":"No API key found in request"`), `401` (`"message":"Unauthorized"`), `200`, `200`.
- **Why both keys work:** authorization is not enabled yet. A credential identifies a caller; it does not say which APIs the caller may use.

Prove a rejected request does not reach Tomcat — send a marked request without a key:

```bash
curl -i 'http://127.0.0.1:8000/api/payment/status?trace=rejected-lab5'
```

Read Kong's access log:

```bash
sudo tail -n 20 /var/log/kong-lab/access.log
```

Wait for Tomcat's access log to flush:

```bash
sleep 10
```

Search Tomcat's log for the marker:

```bash
sudo sh -c 'grep "rejected-lab5" /opt/tomcat/logs/localhost_access_log.*.txt'
```

- **Expected:** 401 in Kong's log; grep finds nothing in Tomcat's log (exit 1 is expected).

## 6. Add authorization and distinguish 401 from 403

Install stage 3 (ACL):

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/03-acl.yml /etc/kong-lab/kong.yml
```

Validate, then reload:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

Wait for the new workers (a reload takes a second or two to apply):

```bash
sleep 5
```

No key:

```bash
curl -i http://127.0.0.1:8000/api/payment/status
```

Blocked partner key:

```bash
curl -i -H 'apikey: blocked-key-456' http://127.0.0.1:8000/api/payment/status
```

Demo key:

```bash
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

- **Expected:**
  - 401 — no identity.
  - 403 with `"message":"You cannot consume this service"` — known caller outside the allowed ACL group.
  - 200 — known caller in `payment-users`.

Read the complete stage 3 file:

```bash
cat ~/ltm/middleware-labs/project-files/kong/03-acl.yml
```

- **Why:** the ACL plugin authorizes a consumer group for this gateway service. It does not check who owns an individual bank account — that stays the application's job.

## 7. Make application 500 and upstream 502 before adding rate limits

- No rate limiter yet, so a 429 cannot hide the backend fault.

**Break** — call the failing page through Kong:

```bash
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/fail
```

Find the stack trace:

```bash
sudo sh -c 'grep -A8 "LAB simulated payment failure" /opt/tomcat/logs/localhost.*.log | tail -n 20'
```

Stop Tomcat:

```bash
sudo systemctl stop tomcat
```

**Observe** — call through Kong with Tomcat down:

```bash
curl --max-time 5 -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

Read Kong's error log:

```bash
sudo tail -n 20 /var/log/kong-lab/error.log
```

**Recover** — start Tomcat:

```bash
sudo systemctl start tomcat
```

- **Expected:**
  - 500 produced by the application.
  - 502 produced by Kong with `"message":"An invalid response was received from the upstream server"` while Tomcat is stopped.
  - `error.log`: `connect() failed (111: Connection refused) while connecting to upstream`
- An `event worker failed to communicate with broker` error from an earlier reload is harmless.

**Verify** (after Tomcat starts):

```bash
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

- **Expected:** 200. A 502 means Tomcat is still starting — wait a few seconds and retry.
- **Why:** a healthy gateway can still return errors when its backend is down.

## 8. Add and test rate limiting

Install stage 4 (rate limit):

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/04-rate-limit.yml /etc/kong-lab/kong.yml
```

Validate, then reload:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

- Limit: 5 requests per minute per authenticated consumer, single node, `policy: local`.

Restart Kong (clean counter; proves the on-disk config survives a restart):

```bash
sudo systemctl restart payment-kong
```

Check Kong is ready via the Admin API (does not use the public quota):

```bash
curl -fsS http://127.0.0.1:8001/status
```

Wait for a fresh minute, send seven calls, then one more with headers — run as one block, with no other public calls for this consumer:

```bash
seconds=$(date +%S)
sleep "$((60 - 10#$seconds))"
for i in 1 2 3 4 5 6 7; do
  curl -s -o /dev/null -w "%{http_code} " \
    -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
done
printf '\n'
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

- **Expected:** `200 200 200 200 200 429 429`, then another 429 with `"message":"API rate limit exceeded"`.
- Check the headers: `X-RateLimit-Limit-Minute: 5`, `X-RateLimit-Remaining-Minute: 0`, and `Retry-After`.
- Fixed minute windows reset at the minute boundary; crossing it, or earlier test traffic, changes the sequence. Local in-memory counters and one worker (set in `kong.conf`) keep counts predictable.
- **If the count differs:** wait for the next minute and repeat only the loop. No Tomcat restart needed.
- **Challenge:** explain why Kong can return 429 while Tomcat is healthy.

## 9. Fault exercise — invalid declarative data, then recover

- Restore stage 3 first so rate limiting cannot mask the check.

Install stage 3:

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/03-acl.yml /etc/kong-lab/kong.yml
```

Validate, then reload:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

Wait for the reload:

```bash
sleep 5
```

**Break** — back up the good file:

```bash
sudo cp /etc/kong-lab/kong.yml ~/lab/backups/kong-good.yml
```

Rename a plugin to one that does not exist:

```bash
sudo sed -i 's/name: key-auth/name: plugin-does-not-exist/' /etc/kong-lab/kong.yml
```

**Observe** — validate the broken file:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf
```

- **Expected:** parse fails:

```text
in 'name': plugin 'plugin-does-not-exist' not enabled; add it to the 'plugins' configuration property
```

- **Do not reload or restart with the invalid file.** The active in-memory config keeps serving.

Prove Kong still serves:

```bash
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

**Recover** — restore the good file:

```bash
sudo cp ~/lab/backups/kong-good.yml /etc/kong-lab/kong.yml
```

**Verify** — validate, then reload:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

- **Expected:** 200 while the file is broken; parse succeeds after recovery.
- A 429 here means the stage 3 reload had not finished — wait a few seconds and repeat the curl.

## 10. Final handoff — restore the complete secured stage

Install stage 4:

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/04-rate-limit.yml /etc/kong-lab/kong.yml
```

Validate, then reload:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

Check Kong's health:

```bash
sudo -u kong-lab kong health -p /var/lib/kong-lab
```

Check the backend services:

```bash
systemctl is-active apache2 nginx tomcat
```

Call through Kong:

```bash
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

Save gateway evidence:

```bash
sudo tail -n 30 /var/log/kong-lab/access.log | tee ~/lab/evidence/lab5-gateway.txt
```

- **If the call returns 429** from an earlier counter: wait for a new minute and retry once.

From another local terminal on the same laptop:

```bash
curl -i -H 'apikey: demo-key-123' http://localhost:8000/api/payment/status
```

- Gateway security applies to port 8000 only. The Lab 4 Apache/Nginx `/payment/` routes are still unprotected comparison paths.
- To force **all** external API callers through Kong, remove or restrict those routes — do the optional lockdown below if that is your final topology.

## 11. Optional final lockdown — make Kong the only external API entry

- Keep the static portal; replace both proxy site files with static-only versions.

Install the static-only Apache site:

```bash
sudo cp ~/ltm/middleware-labs/project-files/config/apache-portal.conf /etc/apache2/sites-available/payment-portal.conf
```

Install the static-only Nginx site:

```bash
sudo cp ~/ltm/middleware-labs/project-files/config/nginx-portal.conf /etc/nginx/sites-available/payment-portal
```

Test and reload Apache:

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
```

Test and reload Nginx:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Old API path through Apache:

```bash
curl -I http://portal.example.test/payment/status
```

Old API path through Nginx:

```bash
curl -I http://portal.example.test:8081/payment/status
```

Static content:

```bash
curl -I http://portal.example.test/health.txt
```

Gateway:

```bash
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

- **Expected:** old proxy paths 404; static health 200; gateway works (subject to quota).
- Portal links to the old proxy paths now return 404 — test the gateway with curl. Tomcat stays loopback-only.
- **To restore Lab 4:** copy `apache-proxy.conf` and `nginx-proxy.conf` back, then test and reload both services.

## Completion table

| Code | Reproduce with | Producer | Evidence |
| --- | --- | --- | --- |
| 200 | valid key, allowed consumer, quota available | App response forwarded by Kong | Both access logs |
| 401 | missing/bad key | Kong key-auth | Gateway log, no backend request |
| 403 | blocked partner key | Kong ACL | Gateway log |
| 404 | `/api/unknown` | Kong router | Gateway log |
| 500 | `/api/payment/fail`, valid key | Application/Tomcat | Stack trace and both logs |
| 502 | stop Tomcat, valid key | Kong proxy | Upstream error, refused direct backend |
| 429 | exceed quota | Kong rate-limiting | Gateway headers/log |

- Use stage 3 when reproducing backend faults so rate limits do not mask the result.
- Name the component that produced each code before naming the owning team.
- References: [DB-less mode](https://developer.konghq.com/gateway/db-less-mode/), [key-auth](https://developer.konghq.com/plugins/key-auth/), [rate limiting](https://developer.konghq.com/plugins/rate-limiting/).
- Package references: [Kong installation](https://developer.konghq.com/gateway/install/), [signed Ubuntu 24.04 repository](https://packages.konghq.com/public/gateway-39/config.deb.txt?distro=ubuntu&codename=noble).
