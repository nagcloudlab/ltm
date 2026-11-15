# Lab 1 — publish the Payment Operations Portal with Apache

**Time:** 75–90 minutes. **Prerequisite:** [student start](00-student-start.md). **Deliverable:** a named Apache website on port 80, with authentication, controlled folder access and request logs.

You are the middleware administrator. The development team has delivered the finished `web/` folder. Your job is to publish and operate it.

## 1. Install Apache and prove the default site works

```bash
sudo apt install -y apache2
sudo systemctl enable --now apache2
systemctl status apache2 --no-pager
pgrep -a apache2
sudo ss -lntp 'sport = :80'
curl -I http://127.0.0.1/
```

Expected: `active (running)`, an Apache listener on port 80 and `HTTP/1.1 200 OK`. Notice the root parent and `www-data` workers:

```bash
ps -eo user,pid,ppid,args | grep '[a]pache2'
sudo apache2ctl -M
sudo apache2ctl -S
```

The service check proves a process exists. The port check proves a listener exists. The HTTP response proves that this URL answers.

## 2. Deploy the prepared static portal

```bash
sudo install -d -m 755 /var/www/payment-portal
sudo cp -a ~/ltm/middleware-labs/project-files/web/. /var/www/payment-portal/
sudo chown -R root:root /var/www/payment-portal
sudo find /var/www/payment-portal -type d -exec chmod 755 {} +
sudo find /var/www/payment-portal -type f -exec chmod 644 {} +
ls -ld /var/www/payment-portal
ls -l /var/www/payment-portal
sudo -u www-data head -n 3 /var/www/payment-portal/index.html
```

Expected: root owns the files; the web worker can read them. Serving static content does not require `www-data` to own or modify the content.

## 3. Create the lab administrator credential

```bash
sudo htpasswd -c /etc/apache2/payment.htpasswd admin
sudo chown root:www-data /etc/apache2/payment.htpasswd
sudo chmod 640 /etc/apache2/payment.htpasswd
```

Choose a classroom-only password and remember it. `-c` creates/replaces a password file; omit it when adding additional users later. Basic authentication here is demonstrated over HTTP on the training network; production use needs HTTPS.

## 4. Install and inspect the virtual host

```bash
cat ~/ltm/middleware-labs/project-files/config/apache-portal.conf
sudo cp ~/ltm/middleware-labs/project-files/config/apache-portal.conf /etc/apache2/sites-available/payment-portal.conf
sudo a2ensite payment-portal
sudo a2dissite 000-default
sudo apache2ctl configtest
```

Expected: `Syntax OK`. Read the file before applying it:

| Directive | Your administration responsibility |
| --- | --- |
| `ServerName` | Match the HTTP Host header |
| `DocumentRoot` | Choose the prepared content folder |
| `<Directory>` | Control access to filesystem paths |
| `Options -Indexes` | Prevent a directory listing |
| `AuthUserFile` | Select the credential file |
| `ErrorLog`, `CustomLog` | Keep evidence for this site |

```bash
sudo systemctl reload apache2
sudo apache2ctl -S
curl -i -H 'Host: portal.example.test' http://127.0.0.1/health.txt
```

Expected: `200` and `WEB PORTAL OK`. The new site is now the only enabled virtual host and also the fallback for unmatched names.

## 5. Resolve the website name on your laptop

```bash
getent hosts portal.example.test
```

Before the local name is configured, no answer is normal. Add the training name once:

```bash
printf '\n127.0.0.1 portal.example.test\n' | sudo tee -a /etc/hosts
getent hosts portal.example.test
curl -I http://portal.example.test/
```

Expected: a loopback address and `200`. Open `http://portal.example.test/` or `http://localhost/` in the browser on this same Ubuntu laptop. The `/etc/hosts` entry you just added applies to both your terminal and browser.

The portal's payment links return 404 until the reverse proxy lab. That is expected: Java has not been deployed yet.

## 6. Observe status codes and logs

Open two local terminal windows. In terminal A:

```bash
sudo tail -f /var/log/apache2/payment-access.log /var/log/apache2/payment-error.log
```

In terminal B:

```bash
curl -I http://portal.example.test/
curl -I http://portal.example.test/missing.html
curl -I http://portal.example.test/private/
curl -I http://portal.example.test/admin/
curl -u admin -I http://portal.example.test/admin/
curl -I http://portal.example.test/old.html
curl -L http://portal.example.test/old.html
```

`curl -u admin` prompts for the password; enter the value created in step 3.

| Request | Expected | Why |
| --- | --- | --- |
| `/` | 200 | The index file exists |
| `/missing.html` | 404 | The file is absent; custom error page is used |
| `/private/` | 403 | Apache's `Require all denied` blocks access |
| `/admin/`, no credential | 401 | Authentication is required |
| `/admin/`, correct credential | 200 | Authenticated user is allowed |
| `/old.html` | 301 | Redirect to the portal index |

Stop tail with Ctrl+C. Count statuses in this guide's combined log format:

```bash
sudo awk '{print $9}' /var/log/apache2/payment-access.log | sort | uniq -c
sudo tail -n 10 /var/log/apache2/payment-access.log | tee ~/lab/evidence/lab1-access.txt
```

Field 9 applies to the configured format; always inspect the format before parsing a different log.

## 7. Fault exercise A — filesystem permissions

Predict the status before you run curl:

```bash
sudo chmod 700 /var/www/payment-portal
curl -I http://portal.example.test/
sudo tail -n 5 /var/log/apache2/payment-error.log
namei -l /var/www/payment-portal/index.html
sudo -u www-data test -r /var/www/payment-portal/index.html; echo "read check exit=$?"
```

Expected: `403`, a permissions-related error, and a failed read check. A worker must traverse every parent directory and read the file.

Recover and prove it:

```bash
sudo chmod 755 /var/www/payment-portal
curl -I http://portal.example.test/
```

Expected: `200`. No reload is required for a filesystem permission change. Do not use `chmod 777`.

## 8. Fault exercise B — a broken configuration, caught safely

```bash
sudo cp /etc/apache2/sites-available/payment-portal.conf ~/lab/backups/apache-lab1.conf
sudo sed -i 's/DocumentRoot/DocumentRot/' /etc/apache2/sites-available/payment-portal.conf
sudo apache2ctl configtest
curl -I http://portal.example.test/
```

Expected: a syntax error naming the file/line, while the existing running configuration still serves `200`. **Do not reload the broken file.**

```bash
sudo cp ~/lab/backups/apache-lab1.conf /etc/apache2/sites-available/payment-portal.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -I http://portal.example.test/
```

## 9. Practice challenge — prove directory listing is disabled

```bash
sudo install -d -m 755 /var/www/payment-portal/downloads
curl -I http://portal.example.test/downloads/
sudo tail -n 5 /var/log/apache2/payment-error.log
```

Expected: `403`, because there is no index file and listings are disabled. Explain why this 403 has a different cause from the `/private/` 403.

## 10. Handoff checklist

```bash
sudo apache2ctl configtest
systemctl is-active apache2
curl -s http://portal.example.test/health.txt
sudo cp /etc/apache2/sites-available/payment-portal.conf ~/lab/backups/apache-lab1-final.conf
```

Save one log line each for 200, 401, 403 and 404. Explain which user serves content, which setting selects the site and why `configtest` runs before reload. Keep Apache running for [Lab 2](02-nginx.md).
