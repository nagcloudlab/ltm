# Your evidence and final incident

Name: __________ Laptop: __________ Date/time zone: __________

- For each lab, copy commands and short relevant output into notes under `~/lab/evidence`.
- Record observations, not only screenshots of green service states.

| Lab | Evidence to collect | Explain to a partner |
| --- | --- | --- |
| Apache | Process/user, :80 listener, 200/401/403/404 logs, recovered config error | Host header vs filesystem permissions |
| Nginx | :8081 listener, matching portal content, 401/403 logs, failed syntax check | Same content, independent web-server config |
| Tomcat | Java process, loopback listener, WAR listing, application 500 stack trace | Tomcat configuration vs app packaging |
| Reverse proxy | Matching frontend/backend request, 502/503/504 evidence | Which hop failed and why |
| Gateway | Route, consumer, 401/403/429 headers/logs, backend 500/502 | Authentication vs authorization vs quota |

## Incident record

- Fill this in for every deliberate fault:

```text
Timestamp and time zone:
User-visible symptom:
Request command and returned status:
Is the process running?
What address/port is listening?
Does the backend answer directly?
Relevant log path and exact line:
Failed hop:
Who should act, and why:
Smallest recovery action:
Successful verification after recovery:
```

## Final incident — diagnose a hidden fault

- Start from Lab 4 proxy config and gateway stage 3 (keys + ACL, no rate limiter). This also restores the proxy routes if you did the optional Lab 5 lockdown.

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

Install Kong stage 3:

```bash
sudo cp ~/ltm/middleware-labs/project-files/kong/03-acl.yml /etc/kong-lab/kong.yml
```

Check and reload Kong:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

- Your partner picks one fault without telling you:
  1. Stop Tomcat.
  2. Change only Apache's upstream port to 8090.
  3. Change only Nginx's document root to a nonexistent directory.
  4. Give you the blocked consumer key to test Kong.
  5. Give you `/payment/fail` to test through a proxy.
- **Procedure:** reproduce the exact symptom → compare a working endpoint → test the backend directly if appropriate → read the correct logs → name the owner → recover. Do not restart every service.
- **Success:** diagnosis cites at least two pieces of evidence; recovery touches only the faulty layer.
- **Verify afterwards:** Apache static health, Nginx static health, direct Tomcat status, both proxy status endpoints and the authorized gateway status all work.
- Return Kong to stage 4 after the exercise.

## Short knowledge check

1. Why can `systemctl is-active` succeed when curl fails?
2. Why do both web servers return the same static page but have different access logs?
3. What changes in the URL when a WAR is named `orders.war`?
4. Why does `proxy_pass http://127.0.0.1:8080;` preserve `/payment/`?
5. Why is a proxy 504 different from a refused TCP connection?
6. Why must other external proxy routes be restricted if Kong should guard every API call?
7. Why can rate limiting hide a backend failure during a test?
8. What evidence would you give developers for a reproducible application 500?
