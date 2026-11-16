# Lab 2 — serve the same portal with Nginx

- **Needs:** [Lab 1](01-apache.md) completed; Apache stays on port 80
- **You build:** Nginx serving the same portal on 8081, independently of Apache
- The application files do not change; only the middleware around them does.

## 1. Verify the starting state

Check Apache serves the portal:

```bash
curl -I http://portal.example.test/
```

List the content folder:

```bash
ls /var/www/payment-portal
```

Check port 80:

```bash
sudo ss -lntp 'sport = :80'
```

Check port 8081:

```bash
sudo ss -lntp 'sport = :8081'
```

- **Expected:** Apache is healthy; 8081 is free.

## 2. Install Nginx and investigate a possible port conflict

- Nginx's default site asks for port 80, which Apache already owns.

Install Nginx:

```bash
sudo apt install -y nginx
```

Check the service:

```bash
systemctl status nginx --no-pager
```

Read its journal:

```bash
sudo journalctl -u nginx -n 20 --no-pager
```

Check who owns port 80:

```bash
sudo ss -lntp 'sport = :80'
```

- **Expected:** Nginx may be stopped or failed; an apt post-install error is also possible.
- Sample line:

```text
nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)
```

- Do not stop Apache to solve this. Read the reason, then move Nginx to 8081.

Remove the default site:

```bash
sudo rm -f /etc/nginx/sites-enabled/default
```

Copy the Lab 1 password file for Nginx:

```bash
sudo install -o root -g www-data -m 640 /etc/apache2/payment.htpasswd /etc/nginx/payment.htpasswd
```

Read the site file:

```bash
cat ~/ltm/middleware-labs/project-files/config/nginx-portal.conf
```

Copy it into Nginx:

```bash
sudo cp ~/ltm/middleware-labs/project-files/config/nginx-portal.conf /etc/nginx/sites-available/payment-portal
```

Enable it with a link:

```bash
sudo ln -sfn /etc/nginx/sites-available/payment-portal /etc/nginx/sites-enabled/payment-portal
```

Test the configuration:

```bash
sudo nginx -t
```

- **Expected:** the syntax test succeeds.

**If apt reported an incomplete configuration earlier**, finish it now.

Complete package setup:

```bash
sudo dpkg --configure -a
```

Enable and start Nginx:

```bash
sudo systemctl enable --now nginx
```

Restart Nginx:

```bash
sudo systemctl restart nginx
```

## 3. Inspect the configuration and prove both services work

Print the full loaded configuration:

```bash
sudo nginx -T
```

Show process owners:

```bash
ps -eo user,pid,ppid,args | grep '[n]ginx'
```

Check port 8081:

```bash
sudo ss -lntp 'sport = :8081'
```

Health check through Nginx:

```bash
curl -i http://portal.example.test:8081/health.txt
```

Health check through Apache:

```bash
curl -i http://portal.example.test/health.txt
```

- **Expected:** both return `WEB PORTAL OK`; the headers name different servers.
- Open `http://localhost:8081/` in your browser.
- **Why:** Nginx uses the same content directory — you have not deployed a second application.

| Apache | Nginx |
| --- | --- |
| `<VirtualHost>` | `server {}` |
| `Listen` / `ServerName` | `listen` / `server_name` |
| `DocumentRoot` | `root` |
| `<Directory>` | Often a `location` rule, but locations select URL paths |
| `a2ensite` | Link the site into `sites-enabled` |
| `apache2ctl configtest` | `nginx -t` |

## 4. Test access rules and authentication

Home page:

```bash
curl -I http://portal.example.test:8081/
```

Missing file:

```bash
curl -I http://portal.example.test:8081/missing.html
```

Blocked folder:

```bash
curl -I http://portal.example.test:8081/private/
```

Admin area, no credential:

```bash
curl -I http://portal.example.test:8081/admin/
```

Admin area with credential (same password as Lab 1):

```bash
curl -u admin -I http://portal.example.test:8081/admin/
```

Old page:

```bash
curl -I http://portal.example.test:8081/old.html
```

Folder without an index:

```bash
curl -I http://portal.example.test:8081/downloads/
```

Status counters:

```bash
curl http://127.0.0.1:8081/nginx_status
```

- **Expected, in order:** `200`, `404`, `403`, `401`, `200`, `301`, `403`, then status counters.
- The password file was copied; later changes to Apache's file do not sync to Nginx.
- The status endpoint allows loopback only; clients from a non-loopback address are denied.

## 5. Follow and compare logs

**Terminal A** — follow both site logs:

```bash
sudo tail -f /var/log/nginx/payment-access.log /var/log/nginx/payment-error.log
```

**Terminal B** — request a missing file:

```bash
curl -I http://portal.example.test:8081/no-such-file.txt
```

Request the blocked folder:

```bash
curl -I http://portal.example.test:8081/private/
```

Count status codes:

```bash
sudo awk '{print $9}' /var/log/nginx/payment-access.log | sort | uniq -c
```

Save the last 10 lines as evidence:

```bash
sudo tail -n 10 /var/log/nginx/payment-access.log | tee ~/lab/evidence/lab2-access.txt
```

- **Expected:** the access log records both requests; the error log explains the rule (`access forbidden by rule`).
- The missing file is a 404 in the access log only: `try_files` answers it without an error-log line.
- Stop tail with Ctrl+C.
- Read the configured site logs; don't assume every request lands in `/var/log/nginx/access.log`.

## 6. Fault exercise A — missing semicolon

**Break** — back up the site file:

```bash
sudo cp /etc/nginx/sites-available/payment-portal ~/lab/backups/nginx-lab2.conf
```

Remove a semicolon:

```bash
sudo sed -i 's/server_tokens off;/server_tokens off/' /etc/nginx/sites-available/payment-portal
```

**Observe** — test the configuration:

```bash
sudo nginx -t
```

Check the running site:

```bash
curl -I http://portal.example.test:8081/
```

- **Expected:** the test fails and names a line near the missing semicolon; the running configuration still works.
- Sample output:

```text
[emerg] invalid number of arguments in "server_tokens" directive in /etc/nginx/sites-enabled/payment-portal:7
```

- **Why:** the next line became part of the same directive, so Nginx reports wrong arguments rather than a missing `;`.
- Do not reload it.

**Recover** — restore the backup:

```bash
sudo cp ~/lab/backups/nginx-lab2.conf /etc/nginx/sites-available/payment-portal
```

Test, then reload only if the test passes:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## 7. Fault exercise B — wrong content root

**Break** — point `root` at a folder that does not exist:

```bash
sudo sed -i 's@root /var/www/payment-portal;@root /var/www/payment-portal-absent;@' /etc/nginx/sites-available/payment-portal
```

Test and reload (the syntax is valid):

```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Observe** — health check through Nginx:

```bash
curl -I http://portal.example.test:8081/health.txt
```

Read the error log:

```bash
sudo tail -n 5 /var/log/nginx/payment-error.log
```

Health check through Apache:

```bash
curl -I http://portal.example.test/health.txt
```

- **Expected:** Nginx gives 404 while Apache still gives 200.
- **If it fails** (still 200): the reload replaces the workers in the background; a request sent within a second can reach an old worker. Repeat the curl.
- **Why:** valid syntax does not prove the path is correct. With `try_files`, some missing-file checks are silent in the error log — inspect `root` and the directory too.

Find the active `root`:

```bash
sudo nginx -T 2>&1 | grep -n 'root /var/www'
```

Check both paths (the second should be absent):

```bash
ls -ld /var/www/payment-portal /var/www/payment-portal-absent
```

**Recover** — restore the backup:

```bash
sudo cp ~/lab/backups/nginx-lab2.conf /etc/nginx/sites-available/payment-portal
```

Test, then reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Verify:**

```bash
curl -I http://portal.example.test:8081/health.txt
```

## 8. Practice challenge and handoff

- Without changing portal files, explain how to identify the answering server from curl headers and logs.

Check both services:

```bash
systemctl is-active apache2 nginx
```

Test the Nginx configuration:

```bash
sudo nginx -t
```

Health check through Apache:

```bash
curl -s http://portal.example.test/health.txt
```

Health check through Nginx:

```bash
curl -s http://portal.example.test:8081/health.txt
```

Back up the final site file:

```bash
sudo cp /etc/nginx/sites-available/payment-portal ~/lab/backups/nginx-lab2-final.conf
```

- Both services must work before [Lab 3 — Tomcat](03-tomcat.md).
- Explain why Apache kept working during the Nginx root-path fault.
