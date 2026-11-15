# Lab 5 — publish and protect the payment API with Kong

**Time:** 75–90 minutes. **Prerequisite:** Lab 4 healthy; repository cloned on this laptop; internet access to install the Kong package. **Deliverable:** the same Tomcat application is exposed through a gateway with API keys, authorization and rate limiting.

```text
curl -> Kong :8000 -> Tomcat 127.0.0.1:8080/payment/
        Admin API 127.0.0.1:8001 (local administrators only)
```

Kong runs as a native Ubuntu service in DB-less mode. Four prepared configuration files add routing, API keys, authorization and rate limiting to the same payment application. No database or application build is needed.

## 1. Verify the backend and install Kong

```bash
curl -s http://127.0.0.1:8080/payment/status
curl -s http://portal.example.test/payment/status
curl -s http://portal.example.test:8081/payment/status
sudo ss -lntp 'sport = :8000'
sudo ss -lntp 'sport = :8001'
```

Expected: three healthy answers; gateway ports unused. This lab pins **Kong OSS 3.9.1**, available as native Ubuntu 24.04 packages for AMD64 and ARM64 in Kong's signed repository. It is a historical classroom version; keep the local-only listener settings supplied here.

Confirm the OS and architecture:

```bash
lsb_release -sc
dpkg --print-architecture
```

Expected: `noble`, and `amd64` or `arm64`. Add the package repository and install:

```bash
sudo apt update
sudo apt install -y curl ca-certificates gnupg lsb-release
curl -fsSL https://packages.konghq.com/public/gateway-39/gpg.key -o /tmp/kong-gateway-39.key
sudo gpg --dearmor --yes -o /usr/share/keyrings/kong-gateway-39-archive-keyring.gpg /tmp/kong-gateway-39.key
curl -fsSL 'https://packages.konghq.com/public/gateway-39/config.deb.txt?distro=ubuntu&codename=noble' -o /tmp/kong-gateway-39.list
sudo install -m 644 /tmp/kong-gateway-39.list /etc/apt/sources.list.d/kong-gateway-39.list
sudo apt update
apt-cache policy kong
sudo apt install -y kong=3.9.1
kong version
command -v kong
```

Expected: version `3.9.1` and `/usr/local/bin/kong`. If the OS, package version or executable path differs, resolve that before continuing. Do not install a different major/minor version for this exercise.

## 2. Install and inspect the prepared configuration

```bash
sudo useradd --system --user-group --home-dir /var/lib/kong-lab --shell /usr/sbin/nologin kong-lab
sudo install -d -o root -g kong-lab -m 750 /etc/kong-lab
sudo install -d -o kong-lab -g kong-lab -m 750 /var/lib/kong-lab /var/log/kong-lab
sudo install -o root -g kong-lab -m 640 ~/ltm/middleware-labs/project-files/config/kong.conf /etc/kong-lab/kong.conf
sudo install -o root -g kong-lab -m 640 ~/ltm/middleware-labs/project-files/kong/01-open.yml /etc/kong-lab/kong.yml
sudo cat /etc/kong-lab/kong.conf
sudo cat /etc/kong-lab/kong.yml
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf
```

Expected: successful parse (exit 0). If the lab account already exists, inspect it with `getent passwd kong-lab` before reusing it.

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

With `strip_path: true`, `/api/payment/status` becomes backend `/payment/status`.

## 3. Start Kong as a systemd service

```bash
cat ~/ltm/middleware-labs/project-files/config/payment-kong.service
sudo cp ~/ltm/middleware-labs/project-files/config/payment-kong.service /etc/systemd/system/payment-kong.service
sudo systemctl daemon-reload
sudo systemctl enable --now payment-kong
systemctl status payment-kong --no-pager
sudo journalctl -u payment-kong -n 30 --no-pager
sudo -u kong-lab kong health -p /var/lib/kong-lab
sudo ss -lntp 'sport = :8000'
sudo ss -lntp 'sport = :8001'
curl -i http://127.0.0.1:8001/status
curl -i http://127.0.0.1:8000/api/payment/status
curl -i http://127.0.0.1:8000/api/payment/balance
```

Expected: active service, healthy Kong, loopback listeners on 8000/8001, and 200 responses. Both Kong and native Tomcat run on this laptop, so Kong can reach the backend's loopback address.

If startup fails, read the journal and `/var/log/kong-lab/error.log`. Do not run a second manual `kong start` alongside systemd.

## 4. Observe gateway routing and logs

Terminal A:

```bash
sudo tail -f /var/log/kong-lab/access.log /var/log/kong-lab/error.log
```

Terminal B:

```bash
curl -i 'http://127.0.0.1:8000/api/payment/status?trace=kong-open'
curl -i http://127.0.0.1:8000/api/unknown
sudo sh -c 'grep "kong-open" /opt/tomcat/logs/localhost_access_log.*.txt'
```

Expected: known route 200, unknown route 404 from Kong. The known route reaches Tomcat; the unmatched route does not. Stop log-following with Ctrl+C. Gateway request logs are in `/var/log/kong-lab/access.log`; upstream errors are in `/var/log/kong-lab/error.log`. The journal records service startup failures.

## 5. Add API-key authentication

Save the current file, install stage 2, parse, and reload only if validation succeeds:

```bash
sudo cp /etc/kong-lab/kong.yml ~/lab/backups/kong-open.yml
sudo cp ~/ltm/middleware-labs/project-files/kong/02-key-auth.yml /etc/kong-lab/kong.yml
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

Allow a few seconds for the new workers, then:

```bash
curl -i http://127.0.0.1:8000/api/payment/status
curl -i -H 'apikey: wrong-key' http://127.0.0.1:8000/api/payment/status
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
curl -i -H 'apikey: blocked-key-456' http://127.0.0.1:8000/api/payment/status
```

Expected: `401`, `401`, `200`, `200`. At this stage both known consumers authenticate, because authorization is not enabled yet. Credentials identify a caller; they do not by themselves establish which APIs the caller may use.

To prove a rejected request does not reach Tomcat, use a unique query marker:

```bash
curl -i 'http://127.0.0.1:8000/api/payment/status?trace=rejected-lab5'
sudo tail -n 20 /var/log/kong-lab/access.log
sudo sh -c 'grep "rejected-lab5" /opt/tomcat/logs/localhost_access_log.*.txt'
```

Expected: 401 in Kong's log; grep finds no corresponding Tomcat request (exit 1 is expected here).

## 6. Add authorization and distinguish 401 from 403

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/03-acl.yml /etc/kong-lab/kong.yml
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

After reload:

```bash
curl -i http://127.0.0.1:8000/api/payment/status
curl -i -H 'apikey: blocked-key-456' http://127.0.0.1:8000/api/payment/status
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

Expected: 401 (no identity), 403 (known caller outside the allowed ACL group), 200 (known caller in `payment-users`). Inspect the complete file:

```bash
cat ~/ltm/middleware-labs/project-files/kong/03-acl.yml
```

The ACL plugin authorizes this gateway service's consumer group. It does not verify business ownership of an individual bank account; application authorization is still the application's responsibility.

## 7. Make application 500 and upstream 502 before adding rate limits

```bash
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/fail
sudo sh -c 'grep -A8 "LAB simulated payment failure" /opt/tomcat/logs/localhost.*.log | tail -n 20'
sudo systemctl stop tomcat
curl --max-time 5 -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
sudo tail -n 20 /var/log/kong-lab/error.log
sudo systemctl start tomcat
```

Expected: application-produced 500, then Kong-produced 502 while Tomcat is stopped. No rate limiter is enabled yet, so 429 cannot hide the backend fault. Wait for Tomcat and verify:

```bash
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

Expected: 200. A healthy gateway can still return an error because its backend is down.

## 8. Add and test rate limiting

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/04-rate-limit.yml /etc/kong-lab/kong.yml
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

The plugin permits 5 requests per minute per authenticated consumer on this single node, with `policy: local`. To get a clean classroom counter and prove the on-disk configuration survives a restart:

```bash
sudo systemctl restart payment-kong
```

After Kong is ready (check Admin API, which does not consume the public quota):

```bash
curl -fsS http://127.0.0.1:8001/status
```

Run the next block at the start of a fresh minute, without making other public calls for this consumer:

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

Expected: `200 200 200 200 200 429 429` followed by another 429. Inspect rate-limit headers and `Retry-After` if present. Fixed minute windows reset at the next minute boundary; a loop that crosses that boundary or earlier test traffic can change the sequence. This fixture uses local in-memory counters and one gateway worker for deterministic classroom counts (configured in `kong.conf`).

If the count differs, wait until the next minute and repeat only the seven-call loop. You do not need to restart Tomcat. Explain why Kong can return 429 while Tomcat is healthy.

## 9. Fault exercise — invalid declarative data, then recover

Restore stage 3 first so rate limiting cannot mask the check:

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/03-acl.yml /etc/kong-lab/kong.yml
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
sudo cp /etc/kong-lab/kong.yml ~/lab/backups/kong-good.yml
sudo sed -i 's/name: key-auth/name: plugin-does-not-exist/' /etc/kong-lab/kong.yml
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf
```

Expected: parse failure for an unknown plugin. **Do not reload or restart with the invalid file.** The active in-memory config continues to serve requests:

```bash
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
sudo cp ~/lab/backups/kong-good.yml /etc/kong-lab/kong.yml
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

Expected: 200 during the file error and a successful parse after recovery.

## 10. Final handoff — restore the complete secured stage

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/04-rate-limit.yml /etc/kong-lab/kong.yml
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
sudo -u kong-lab kong health -p /var/lib/kong-lab
systemctl is-active apache2 nginx tomcat
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
sudo tail -n 30 /var/log/kong-lab/access.log | tee ~/lab/evidence/lab5-gateway.txt
```

If the last call returns 429 from an earlier counter, wait for a new minute and retry once. From another local terminal on the same laptop:

```bash
curl -i -H 'apikey: demo-key-123' http://localhost:8000/api/payment/status
```

The gateway's security applies to port 8000 only. Apache/Nginx `/payment/` routes intentionally still provide unprotected comparison paths from Lab 4. To force **all** external API callers through Kong, those alternative routes must be removed or restricted; complete the optional lockdown below if this is your intended final topology.

## 11. Optional final lockdown — make Kong the only external API entry

Keep the static portal, but replace both proxy site files with their static-only counterparts:

```bash
sudo cp ~/ltm/middleware-labs/project-files/config/apache-portal.conf /etc/apache2/sites-available/payment-portal.conf
sudo cp ~/ltm/middleware-labs/project-files/config/nginx-portal.conf /etc/nginx/sites-available/payment-portal
sudo apache2ctl configtest && sudo systemctl reload apache2
sudo nginx -t && sudo systemctl reload nginx
curl -I http://portal.example.test/payment/status
curl -I http://portal.example.test:8081/payment/status
curl -I http://portal.example.test/health.txt
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

Expected: old public proxy API paths are 404, static health is 200 and the gateway still works (subject to quota). Portal links to the old proxy paths will now return 404; test the gateway using curl. Tomcat remains loopback only. Restore Lab 4 by copying `apache-proxy.conf` and `nginx-proxy.conf` back and testing/reloading both services.

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

Use stage 3 when reproducing backend faults so rate limits do not mask the result. Explain which component made each code before naming the owning team.

References: [DB-less mode](https://developer.konghq.com/gateway/db-less-mode/), [key-auth](https://developer.konghq.com/plugins/key-auth/), [rate limiting](https://developer.konghq.com/plugins/rate-limiting/).

Package references: [Kong installation](https://developer.konghq.com/gateway/install/), [signed Ubuntu 24.04 repository](https://packages.konghq.com/public/gateway-39/config.deb.txt?distro=ubuntu&codename=noble).
