# Lab 1 — publish the Payment Operations Portal with Apache

- **Needs:** [student start](00-student-start.md)
- **You build:** a named Apache website on port 80 with authentication, folder access control and request logs
- **Your role:** middleware administrator; the development team has delivered the finished `web/` folder — you publish and operate it

## 1. Install Apache and prove the default site works

- Three separate proofs: the service runs, the port listens, the URL answers.

Install Apache:

```bash
sudo apt install -y apache2
```

Enable and start the service:

```bash
sudo systemctl enable --now apache2
```

Check the service:

```bash
systemctl status apache2 --no-pager
```

List Apache processes:

```bash
pgrep -a apache2
```

Check port 80:

```bash
sudo ss -lntp 'sport = :80'
```

Request the default page:

```bash
curl -I http://127.0.0.1/
```

- **Expected:** `active (running)`, an Apache listener on port 80, `HTTP/1.1 200 OK`.

Show process owners (root parent, `www-data` workers):

```bash
ps -eo user,pid,ppid,args | grep '[a]pache2'
```

List loaded modules:

```bash
sudo apache2ctl -M
```

Show virtual hosts:

```bash
sudo apache2ctl -S
```

## 2. Deploy the prepared static portal

- Root owns the content; the `www-data` worker only needs to read it.

Create the content folder:

```bash
sudo install -d -m 755 /var/www/payment-portal
```

Copy the portal files:

```bash
sudo cp -a ~/ltm/middleware-labs/project-files/web/. /var/www/payment-portal/
```

Make root the owner:

```bash
sudo chown -R root:root /var/www/payment-portal
```

Set folders to 755:

```bash
sudo find /var/www/payment-portal -type d -exec chmod 755 {} +
```

Set files to 644:

```bash
sudo find /var/www/payment-portal -type f -exec chmod 644 {} +
```

Check the folder:

```bash
ls -ld /var/www/payment-portal
```

Check the files:

```bash
ls -l /var/www/payment-portal
```

Read a file as the web worker:

```bash
sudo -u www-data head -n 3 /var/www/payment-portal/index.html
```

- **Expected:** root owns the files; `www-data` can read them.
- **Why:** serving static content does not require `www-data` to own or modify it.

## 3. Create the lab administrator credential

Create the password file and the `admin` user (choose a classroom-only password and remember it):

```bash
sudo htpasswd -c /etc/apache2/payment.htpasswd admin
```

Let the web group read it:

```bash
sudo chown root:www-data /etc/apache2/payment.htpasswd
```

Restrict permissions:

```bash
sudo chmod 640 /etc/apache2/payment.htpasswd
```

- `-c` creates/replaces the file; omit it when adding more users later.
- Basic authentication over HTTP is for the training network only; production needs HTTPS.

## 4. Install and inspect the virtual host

Read the site file before applying it:

```bash
cat ~/ltm/middleware-labs/project-files/config/apache-portal.conf
```

| Directive | Your responsibility |
| --- | --- |
| `ServerName` | Match the HTTP Host header |
| `DocumentRoot` | Choose the prepared content folder |
| `<Directory>` | Control access to filesystem paths |
| `Options -Indexes` | Prevent a directory listing |
| `AuthUserFile` | Select the credential file |
| `ErrorLog`, `CustomLog` | Keep evidence for this site |

Copy it into Apache:

```bash
sudo cp ~/ltm/middleware-labs/project-files/config/apache-portal.conf /etc/apache2/sites-available/payment-portal.conf
```

Enable the portal site:

```bash
sudo a2ensite payment-portal
```

Disable the default site:

```bash
sudo a2dissite 000-default
```

Test the configuration:

```bash
sudo apache2ctl configtest
```

- **Expected:** `Syntax OK`.
- A preceding `AH00558: apache2: Could not reliably determine the server's fully qualified domain name` warning is harmless: the site sets its own `ServerName`.

Apply it:

```bash
sudo systemctl reload apache2
```

Show virtual hosts:

```bash
sudo apache2ctl -S
```

Request the health file with the site's Host header:

```bash
curl -i -H 'Host: portal.example.test' http://127.0.0.1/health.txt
```

- **Expected:** `200` and `WEB PORTAL OK`.
- The new site is the only enabled virtual host, so it is also the fallback for unmatched names.

## 5. Resolve the website name on your laptop

Look up the name (no answer is normal at this point):

```bash
getent hosts portal.example.test
```

Add the training name once:

```bash
printf '\n127.0.0.1 portal.example.test\n' | sudo tee -a /etc/hosts
```

Look it up again:

```bash
getent hosts portal.example.test
```

Request the site by name:

```bash
curl -I http://portal.example.test/
```

- **Expected:** a loopback address and `200`.
- Open `http://portal.example.test/` or `http://localhost/` in the browser on this laptop; `/etc/hosts` applies to both terminal and browser.
- Payment links return 404 until the reverse proxy lab — Java is not deployed yet.

## 6. Observe status codes and logs

- Open two local terminals.

**Terminal A** — follow both site logs:

```bash
sudo tail -f /var/log/apache2/payment-access.log /var/log/apache2/payment-error.log
```

**Terminal B** — send each request and watch terminal A.

Home page:

```bash
curl -I http://portal.example.test/
```

Missing file:

```bash
curl -I http://portal.example.test/missing.html
```

Blocked folder:

```bash
curl -I http://portal.example.test/private/
```

Admin area, no credential:

```bash
curl -I http://portal.example.test/admin/
```

Admin area with credential (enter the password from step 3):

```bash
curl -u admin -I http://portal.example.test/admin/
```

Old page:

```bash
curl -I http://portal.example.test/old.html
```

Old page, following the redirect:

```bash
curl -L http://portal.example.test/old.html
```

| Request | Expected | Why |
| --- | --- | --- |
| `/` | 200 | The index file exists |
| `/missing.html` | 404 | File absent; custom error page used |
| `/private/` | 403 | `Require all denied` blocks access |
| `/admin/`, no credential | 401 | Authentication required |
| `/admin/`, correct credential | 200 | Authenticated user allowed |
| `/old.html` | 301 | Redirect to the portal index |

- Stop tail with Ctrl+C.

Count status codes (field 9 in this site's combined log format):

```bash
sudo awk '{print $9}' /var/log/apache2/payment-access.log | sort | uniq -c
```

Save the last 10 lines as evidence:

```bash
sudo tail -n 10 /var/log/apache2/payment-access.log | tee ~/lab/evidence/lab1-access.txt
```

- **Why:** field 9 is only right for this format; always inspect the format before parsing a different log.

## 7. Fault exercise A — filesystem permissions

- Predict the status before you run curl.

**Break** — remove access for everyone but root:

```bash
sudo chmod 700 /var/www/payment-portal
```

**Observe** — request the page:

```bash
curl -I http://portal.example.test/
```

Read the error log:

```bash
sudo tail -n 5 /var/log/apache2/payment-error.log
```

Show permissions on every part of the path:

```bash
namei -l /var/www/payment-portal/index.html
```

Test read access as the web worker:

```bash
sudo -u www-data test -r /var/www/payment-portal/index.html; echo "read check exit=$?"
```

- **Expected:** `403`, a permissions error, and `read check exit=1`.
- Sample line:

```text
(13)Permission denied: [client 127.0.0.1:37946] AH00035: access to /index.html denied (filesystem path '/var/www/payment-portal/index.html') because search permissions are missing on a component of the path
```

- The last lines may name other index candidates such as `/index.htm`; same cause.
- **Why:** a worker must traverse every parent directory and read the file.

**Recover** — restore the folder mode:

```bash
sudo chmod 755 /var/www/payment-portal
```

**Verify:**

```bash
curl -I http://portal.example.test/
```

- **Expected:** `200`. No reload needed for a filesystem permission change.
- Do not use `chmod 777`.

## 8. Fault exercise B — a broken configuration, caught safely

**Break** — back up the site file:

```bash
sudo cp /etc/apache2/sites-available/payment-portal.conf ~/lab/backups/apache-lab1.conf
```

Introduce a typo:

```bash
sudo sed -i 's/DocumentRoot/DocumentRot/' /etc/apache2/sites-available/payment-portal.conf
```

**Observe** — test the configuration:

```bash
sudo apache2ctl configtest
```

Check the running site:

```bash
curl -I http://portal.example.test/
```

- **Expected:** a syntax error naming the file and line, while the running configuration still serves `200`.
- Sample output:

```text
AH00526: Syntax error on line 3 of /etc/apache2/sites-enabled/payment-portal.conf:
Invalid command 'DocumentRot', perhaps misspelled or defined by a module not included in the server configuration
```

- The path shown is the `sites-enabled` link to the file you edited.
- **Do not reload the broken file.**

**Recover** — restore the backup:

```bash
sudo cp ~/lab/backups/apache-lab1.conf /etc/apache2/sites-available/payment-portal.conf
```

Test, then reload only if the test passes:

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
```

**Verify:**

```bash
curl -I http://portal.example.test/
```

## 9. Practice challenge — prove directory listing is disabled

Create a folder with no index file:

```bash
sudo install -d -m 755 /var/www/payment-portal/downloads
```

Request it:

```bash
curl -I http://portal.example.test/downloads/
```

Read the error log:

```bash
sudo tail -n 5 /var/log/apache2/payment-error.log
```

- **Expected:** `403` and `AH01276: Cannot serve directory /var/www/payment-portal/downloads/: No matching DirectoryIndex ... forbidden by Options directive`.
- Explain why this 403 has a different cause from the `/private/` 403.

## 10. Handoff checklist

Test the configuration:

```bash
sudo apache2ctl configtest
```

Check the service:

```bash
systemctl is-active apache2
```

Check the health file:

```bash
curl -s http://portal.example.test/health.txt
```

Back up the final site file:

```bash
sudo cp /etc/apache2/sites-available/payment-portal.conf ~/lab/backups/apache-lab1-final.conf
```

- Save one log line each for 200, 401, 403 and 404.
- Explain: which user serves content, which setting selects the site, why `configtest` runs before reload.
- Keep Apache running for [Lab 2](02-nginx.md).
