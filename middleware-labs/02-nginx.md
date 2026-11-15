# Lab 2 — serve the same portal with Nginx

**Time:** 60–75 minutes. **Prerequisite:** Lab 1 completed; Apache remains on port 80. **Deliverable:** Nginx serves the same portal on 8081, independently of Apache.

The application files do not change. You are changing the middleware around them.

## 1. Verify the starting state

```bash
curl -I http://portal.example.test/
ls /var/www/payment-portal
sudo ss -lntp 'sport = :80'
sudo ss -lntp 'sport = :8081'
```

Expected: Apache is healthy; 8081 is free.

## 2. Install Nginx and investigate a possible port conflict

```bash
sudo apt install -y nginx
systemctl status nginx --no-pager
sudo journalctl -u nginx -n 20 --no-pager
sudo ss -lntp 'sport = :80'
```

Nginx's default site requests port 80, which Apache already owns. Depending on package installation behavior, Nginx may be stopped or failed; an apt post-install error is also possible. Do not stop Apache to solve this. Read the reason, then configure Nginx on 8081.

```bash
sudo rm -f /etc/nginx/sites-enabled/default
sudo install -o root -g www-data -m 640 /etc/apache2/payment.htpasswd /etc/nginx/payment.htpasswd
cat ~/ltm/middleware-labs/project-files/config/nginx-portal.conf
sudo cp ~/ltm/middleware-labs/project-files/config/nginx-portal.conf /etc/nginx/sites-available/payment-portal
sudo ln -sfn /etc/nginx/sites-available/payment-portal /etc/nginx/sites-enabled/payment-portal
sudo nginx -t
```

Expected: syntax test succeeds. If apt reported an incomplete configuration in the earlier installation step, complete it now:

```bash
sudo dpkg --configure -a
sudo systemctl enable --now nginx
sudo systemctl restart nginx
```

## 3. Inspect the configuration and prove both services work

```bash
sudo nginx -T
ps -eo user,pid,ppid,args | grep '[n]ginx'
sudo ss -lntp 'sport = :8081'
curl -i http://portal.example.test:8081/health.txt
curl -i http://portal.example.test/health.txt
```

Expected: both return `WEB PORTAL OK`; the headers identify different servers. Open `http://localhost:8081/` on your laptop. Nginx uses the exact same content directory; you have not deployed a second application.

| Apache concept | Nginx concept |
| --- | --- |
| `<VirtualHost>` | `server {}` |
| `Listen` | `listen` |
| `ServerName` | `server_name` |
| `DocumentRoot` | `root` |
| `<Directory>` | Often a `location` rule, but locations select URL paths |
| `a2ensite` | Link the site into `sites-enabled` |
| `apache2ctl configtest` | `nginx -t` |

## 4. Test access rules and authentication

```bash
curl -I http://portal.example.test:8081/
curl -I http://portal.example.test:8081/missing.html
curl -I http://portal.example.test:8081/private/
curl -I http://portal.example.test:8081/admin/
curl -u admin -I http://portal.example.test:8081/admin/
curl -I http://portal.example.test:8081/old.html
curl -I http://portal.example.test:8081/downloads/
curl http://127.0.0.1:8081/nginx_status
```

Expected in order: `200`, `404`, `403`, `401`, `200`, `301`, `403`, then status counters. Enter the same admin password as Lab 1. The password file was copied; later changes to Apache's password file do not automatically synchronize it.

The status endpoint is restricted to loopback. Your local curl can access it; clients connecting through a non-loopback network address are denied.

## 5. Follow and compare logs

Terminal A:

```bash
sudo tail -f /var/log/nginx/payment-access.log /var/log/nginx/payment-error.log
```

Terminal B:

```bash
curl -I http://portal.example.test:8081/no-such-file.txt
curl -I http://portal.example.test:8081/private/
sudo awk '{print $9}' /var/log/nginx/payment-access.log | sort | uniq -c
sudo tail -n 10 /var/log/nginx/payment-access.log | tee ~/lab/evidence/lab2-access.txt
```

Expected: the access log records both requests; the error log explains a missing file or an access rule. Stop tail with Ctrl+C. Read the configured site logs rather than assuming every site's requests go into `/var/log/nginx/access.log`.

## 6. Fault exercise A — missing semicolon

```bash
sudo cp /etc/nginx/sites-available/payment-portal ~/lab/backups/nginx-lab2.conf
sudo sed -i 's/server_tokens off;/server_tokens off/' /etc/nginx/sites-available/payment-portal
sudo nginx -t
curl -I http://portal.example.test:8081/
```

Expected: configuration test fails and names a line near the missing semicolon; the current running configuration still works. Do not reload it.

```bash
sudo cp ~/lab/backups/nginx-lab2.conf /etc/nginx/sites-available/payment-portal
sudo nginx -t && sudo systemctl reload nginx
```

## 7. Fault exercise B — wrong content root

```bash
sudo sed -i 's@root /var/www/payment-portal;@root /var/www/payment-portal-absent;@' /etc/nginx/sites-available/payment-portal
sudo nginx -t && sudo systemctl reload nginx
curl -I http://portal.example.test:8081/health.txt
sudo tail -n 5 /var/log/nginx/payment-error.log
curl -I http://portal.example.test/health.txt
```

Expected: Nginx gives 404 while Apache still gives 200. Syntax validity does not prove the filesystem path is correct. With `try_files`, some missing-file checks are silent in the error log; inspect `root` and the directory as well.

```bash
sudo nginx -T 2>&1 | grep -n 'root /var/www'
ls -ld /var/www/payment-portal /var/www/payment-portal-absent
```

The second path should be absent. Recover:

```bash
sudo cp ~/lab/backups/nginx-lab2.conf /etc/nginx/sites-available/payment-portal
sudo nginx -t && sudo systemctl reload nginx
curl -I http://portal.example.test:8081/health.txt
```

## 8. Practice challenge and handoff

Without changing portal files, explain how you would identify the answering server from curl headers and logs. Then verify:

```bash
systemctl is-active apache2 nginx
sudo nginx -t
curl -s http://portal.example.test/health.txt
curl -s http://portal.example.test:8081/health.txt
sudo cp /etc/nginx/sites-available/payment-portal ~/lab/backups/nginx-lab2-final.conf
```

Both services must work before [Lab 3 — Tomcat](03-tomcat.md). Explain why Apache kept working during the Nginx root-path fault.
