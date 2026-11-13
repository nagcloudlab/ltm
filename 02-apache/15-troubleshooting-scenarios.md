# 15 · Troubleshooting scenarios: break, read the evidence, fix, verify

**Time:** 90 min · **Work:** in pairs (one breaks, the other diagnoses without looking)

**You will learn:** thirteen real failures, each with the same five steps. The goal is the habit: **symptom → the right log → the exact line → the cause → the fix → proof**.

Uses the sites from earlier topics: default site (`localhost`), `admin.example.com` (topic 05, log format `paybank` from topic 13), `reports` on port 8090, the `/blog/` folder (topic 07) and `/cgi-bin/slow.sh` (topic 13).

---

## The five steps (every scenario)

- **1 Symptom:** what does `curl -I` (or `-v`) say? Refused, timeout, a status code, or the wrong page?
- **2 Which log:** Apache never saw it (refused, timeout) → `systemctl status`, `journalctl -u apache2`, `ss`. Apache answered → the site's **access** log for *what*, the site's **error** log for *why*.
- **3 The line:** find the line at the same time as your test (`tail -n 3`, or `grep` the time).
- **4 Cause and fix:** one change, then `configtest && reload`.
- **5 Verify:** the same curl again, and a clean log line.

Before you start, keep one terminal open on the logs:

```bash
sudo tail -F /var/log/apache2/error.log /var/log/apache2/admin-error.log /var/log/apache2/admin-access.log
```

### Anatomy of an error-log line

```text
[Fri Nov 13 00:47:01.731514 2026] [mpm_event:error] [pid 14109:tid 281473287815200] [client 127.0.0.1:47262] AH00484: server reached MaxRequestWorkers setting, ...
 └ when (to the microsecond)        └ module:level    └ process : thread             └ who (not always)       └ code: message
```

- **module** tells you which part of Apache complained: `core`, `authz_core` (Require), `auth_basic` (passwords), `autoindex` (listings), `ssl`, `mpm_event` (workers), `rewrite`.
- **level** tells you how bad: `emerg` (Apache stops) › `alert` › `crit` › `error` › `warn` › `notice` (start/stop messages, normal).
- **AHnnnnn** is a fixed code: search it in the docs or the web.

---

## Scenario 1 · A typo, then a restart: every site is down

**Break it**

```bash
sudo cp /etc/apache2/sites-available/admin.conf /etc/apache2/sites-available/admin.conf.s1
sudo sed -i 's/ServerName/ServerNmae/' /etc/apache2/sites-available/admin.conf
sudo systemctl restart apache2
```

**Symptom**

```bash
curl -I http://localhost/
```

- `curl: (7) Failed to connect to localhost port 80 … Couldn't connect to server`: **all** sites, not only admin.

**Evidence**

```bash
systemctl status apache2 --no-pager | head -n 4
journalctl -u apache2 -n 6 --no-pager
sudo apache2ctl configtest
```

Sample line:

```text
AH00526: Syntax error on line 2 of /etc/apache2/sites-enabled/admin.conf:
Invalid command 'ServerNmae', perhaps misspelled or defined by a module not included in the server configuration
```

- `Active: failed`: Apache is not running, so its own logs have nothing about your curl.
- `journalctl` and `configtest` give the file, the line number and the word.

**Fix and verify**

```bash
sudo cp /etc/apache2/sites-available/admin.conf.s1 /etc/apache2/sites-available/admin.conf
sudo apache2ctl configtest && sudo systemctl start apache2
curl -sI http://localhost/ | head -n 1
```

- Lesson: `configtest && reload`, never a bare `restart`.

## Scenario 2 · The port is already taken

**Break it**

```bash
sudo systemctl stop apache2
sudo python3 -m http.server 8090 --directory /tmp > /dev/null 2>&1 &
sleep 2
sudo systemctl start apache2
```

**Symptom**

- `Job for apache2.service failed`. Port 80 is refused too: Apache could not open **one** of its ports, so it did not start at all.

**Evidence**

```bash
journalctl -u apache2 -n 10 --no-pager | grep -E "AH00072|listening|AH00015"
sudo ss -lntp 'sport = :8090'
```

Sample lines:

```text
(98)Address already in use: AH00072: make_sock: could not bind to address 0.0.0.0:8090
no listening sockets available, shutting down
AH00015: Unable to open logs
```

- `(98)` = Linux error 98, "address already in use".
- `ss` names the owner: `users:(("python3",pid=…))`.

**Fix and verify**

```bash
sudo fuser -v 8090/tcp
sudo fuser -k 8090/tcp
sudo systemctl start apache2
sudo ss -lntp | grep apache2
```

## Scenario 3 · Permission denied (13) on a file

**Break it**

```bash
sudo chmod 600 /var/www/admin/index.html
```

**Symptom**

```bash
curl -I http://admin.example.com/
```

- `403 Forbidden`.

**Evidence**

```bash
sudo tail -n 1 /var/log/apache2/admin-error.log
namei -l /var/www/admin/index.html
```

Sample line:

```text
[Fri Nov 13 01:02:11.120331 2026] [core:error] [pid 15020:tid 281473287815200] (13)Permission denied: [client 127.0.0.1:40122] AH00132: file permissions deny server access: /var/www/admin/index.html
```

- `(13)Permission denied` = Linux said no, not Apache's rules.
- `AH00132 … file permissions` = the **file**; `AH00035 … search permissions` = a **folder** on the path.
- `namei -l` shows `-rw-------`: www-data cannot read it.

**Fix and verify**

```bash
sudo chmod 644 /var/www/admin/index.html
curl -sI http://admin.example.com/ | head -n 1
```

## Scenario 4 · DocumentRoot points to a folder that does not exist

**Break it**

```bash
sudo cp /etc/apache2/sites-available/admin.conf /etc/apache2/sites-available/admin.conf.s4
sudo sed -i 's#DocumentRoot /var/www/admin#DocumentRoot /var/www/admln#' /etc/apache2/sites-available/admin.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

**Symptom**

```bash
curl -I http://admin.example.com/
```

- `404 Not Found` for the home page, which "is definitely there".

**Evidence**

```bash
sudo tail -n 1 /var/log/apache2/admin-access.log
sudo tail -n 1 /var/log/apache2/admin-error.log
sudo apache2ctl -t -D DUMP_VHOSTS 2>&1 | grep admin
grep -n DocumentRoot /etc/apache2/sites-available/admin.conf
```

Sample line (configtest):

```text
AH00112: Warning: DocumentRoot [/var/www/admln] does not exist
Syntax OK
```

- The warning was printed **before** `Syntax OK`; the reload went ahead anyway.
- The error log has **no** new line: a 404 is not an Apache error. Only the access log shows it.

**Fix and verify**

```bash
sudo cp /etc/apache2/sites-available/admin.conf.s4 /etc/apache2/sites-available/admin.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -sI http://admin.example.com/ | head -n 1
```

## Scenario 5 · The wrong website answers

**Break it**

```bash
sudo cp /etc/apache2/sites-available/admin.conf /etc/apache2/sites-available/admin.conf.s5
sudo sed -i 's/ServerName admin.example.com/ServerName admn.example.com/' /etc/apache2/sites-available/admin.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
```

**Symptom**

```bash
curl -s http://admin.example.com/ | grep -o "<title>.*</title>"
```

- `200 OK`, but the **Apache2 Ubuntu Default Page**. No error anywhere.

**Evidence**

```bash
sudo apache2ctl -S 2>&1 | grep -E "default server|namevhost"
sudo tail -n 1 /var/log/apache2/access.log
```

- `-S` lists `namevhost admn.example.com`: a typo. No site claims `admin.example.com`, so the **default server** answers.
- The request was logged in the **default** site's `access.log`, not in `admin-access.log`: "my request is not in the log" often means "another site got it".

**Fix and verify**

```bash
sudo cp /etc/apache2/sites-available/admin.conf.s5 /etc/apache2/sites-available/admin.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -s http://admin.example.com/ | head -n 1
```

## Scenario 6 · 403 from a Require rule, and 403 from a listing

**Break it**

```bash
sudo mkdir -p /var/www/admin/reports
sudo touch /var/www/admin/reports/q3.pdf
sudo cp /etc/apache2/sites-available/admin.conf /etc/apache2/sites-available/admin.conf.s6
sudo vi /etc/apache2/sites-available/admin.conf
```

Inside the VirtualHost add:

```apache
    <Directory /var/www/admin/secret>
        Require all denied
    </Directory>
```

```bash
sudo mkdir -p /var/www/admin/secret
echo "keys" | sudo tee /var/www/admin/secret/index.html
sudo apache2ctl configtest && sudo systemctl reload apache2
```

**Symptom**

```bash
curl -sI http://admin.example.com/secret/ | head -n 1
curl -sI http://admin.example.com/reports/ | head -n 1
```

- Both `403 Forbidden`, for two different reasons.

**Evidence**

```bash
sudo tail -n 2 /var/log/apache2/admin-error.log
```

Sample lines:

```text
[Fri Nov 13 01:05:40.412398 2026] [authz_core:error] [pid 15301:tid 281473287815200] [client 127.0.0.1:40310] AH01630: client denied by server configuration: /var/www/admin/secret/
[Fri Nov 13 01:05:40.420115 2026] [autoindex:error] [pid 15301:tid 281473279426848] [client 127.0.0.1:40312] AH01276: Cannot serve directory /var/www/admin/reports/: No matching DirectoryIndex (index.html,index.cgi,index.pl,index.php,index.xhtml,index.htm) found, and server-generated directory index forbidden by Options directive
```

| Code | Module | Cause | Fix |
|---|---|---|---|
| `AH01630` | `authz_core` | a `Require` rule said no | change the rule, if the access is wanted |
| `AH01276` | `autoindex` | a folder with no index file, listings off | add an `index.html` (do **not** turn listings on) |

**Fix and verify**

```bash
echo "<h1>Reports</h1>" | sudo tee /var/www/admin/reports/index.html
curl -sI http://admin.example.com/reports/ | head -n 1
sudo cp /etc/apache2/sites-available/admin.conf.s6 /etc/apache2/sites-available/admin.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
```

## Scenario 7 · A developer's .htaccess gives 500

**Break it** (a line copied from an old PHP server)

```bash
echo "php_value upload_max_filesize 64M" | sudo tee /var/www/html/blog/.htaccess
```

**Symptom**

```bash
curl -sI http://localhost/blog/ | head -n 1
sudo apache2ctl configtest
```

- `500 Internal Server Error` for every page in `/blog/`, but configtest says `Syntax OK`: it never reads `.htaccess` files.

**Evidence**

```bash
sudo tail -n 1 /var/log/apache2/error.log
```

Sample line:

```text
[Fri Nov 13 01:08:02.991120 2026] [core:alert] [pid 15480:tid 281473287815200] [client 127.0.0.1:40422] /var/www/html/blog/.htaccess: Invalid command 'php_value', perhaps misspelled or defined by a module not included in the server configuration
```

- `core:alert` + the `.htaccess` path + the word.
- "perhaps misspelled **or defined by a module not included**": a typo, or a line for a module this server does not have (`php_value` needs mod_php, which is not installed).

**Fix and verify**

```bash
sudo rm /var/www/html/blog/.htaccess
curl -sI http://localhost/blog/ | head -n 1
```

- No reload needed: `.htaccess` is read on every request.

## Scenario 8 · 401 that never accepts the password

**Break it**

```bash
sudo mv /etc/apache2/.htpasswd /etc/apache2/.htpasswd.moved
```

**Symptom**

```bash
curl -sI -u admin:yourpassword http://localhost/admin/ | head -n 1
```

- `500 Internal Server Error` even with the right password.

**Evidence**

```bash
sudo tail -n 1 /var/log/apache2/error.log
```

Sample line:

```text
[Fri Nov 13 01:10:15.204551 2026] [authn_file:error] [pid 15622:tid 281473287815200] (2)No such file or directory: [client 127.0.0.1:40510] AH01620: Could not open password file: /etc/apache2/.htpasswd
```

- `(2)No such file or directory` = Linux error 2.

| Error log | Means |
|---|---|
| `AH01620 Could not open password file` | the AuthUserFile is missing or unreadable → **500** |
| `AH01617 … Password Mismatch` | right user, wrong password → 401 |
| `AH01618 user … not found` | user not in the file → 401 |
| nothing | no password sent yet → 401 (normal first step) |

**Fix and verify**

```bash
sudo mv /etc/apache2/.htpasswd.moved /etc/apache2/.htpasswd
curl -sI -u admin:yourpassword http://localhost/admin/ | head -n 1
curl -sI -u admin:wrong http://localhost/admin/ | head -n 1
sudo tail -n 1 /var/log/apache2/error.log
```

## Scenario 9 · A redirect loop

**Break it**

```bash
sudo cp /etc/apache2/sites-available/admin.conf /etc/apache2/sites-available/admin.conf.s9
sudo vi /etc/apache2/sites-available/admin.conf
```

Inside the VirtualHost, after the `RewriteEngine On` line from topic 13, add a rule that redirects `/shop/` to itself:

```apache
    RewriteRule ^/shop/(.*)$ /shop/$1 [R=302,L]
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
```

**Symptom**

```bash
curl -sS -L --max-redirs 5 -o /dev/null http://admin.example.com/shop/a.html
```

- `curl: (47) Maximum (5) redirects followed`. A browser shows **ERR_TOO_MANY_REDIRECTS** / "redirected you too many times".

**Evidence**

```bash
sudo tail -n 4 /var/log/apache2/admin-access.log
curl -sI http://admin.example.com/shop/a.html | grep -E "HTTP|Location"
```

- The access log shows the **same** path again and again, each with `302`.
- `Location` points to the URL you asked for: the rule matches its own result.
- `LogLevel warn rewrite:trace3` (topic 13) shows the rule matching every time.

**Fix and verify**

```bash
sudo cp /etc/apache2/sites-available/admin.conf.s9 /etc/apache2/sites-available/admin.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -sI http://admin.example.com/shop/a.html | head -n 1
```

- Common real causes: http→https redirect on both sites, or a rule whose target matches its own pattern.

## Scenario 10 · "The site is slow": find the slow URL

**Break it**

```bash
for i in 1 2 3; do curl -s -o /dev/null http://admin.example.com/; done
for i in 1 2; do curl -s -o /dev/null "http://admin.example.com/cgi-bin/slow.sh?4"; done
curl -s -o /dev/null http://admin.example.com/nothing.html
```

**Evidence**

```bash
sudo tail -n 6 /var/log/apache2/admin-access.log
sudo awk '$NF > 1000000 {printf "%.2f s %s %s\n", $NF/1000000, $4, $7}' /var/log/apache2/admin-access.log | tail -n 3
curl -s "http://localhost/server-status?auto" | grep -E "BusyWorkers|IdleWorkers"
uptime
```

- `%D` (last field) is about `4000000` for the slow page and under `1000` for the rest.
- Workers mostly idle, load low: Apache is fine. The slowness is **behind** one URL (the script, in real life a database).

**Fix and verify**

- Send the application team the URL, the times and the `%D` values. Apache cannot make that page faster.

## Scenario 11 · Disk full from logs, and space that does not come back

**Break it** (a 300 MB log grows quietly)

```bash
df -h /var/log
sudo fallocate -l 300M /var/log/apache2/reports-access.log
df -h /var/log
sudo du -sh /var/log/apache2/* | sort -h | tail -n 3
```

**The mistake:** deleting the big log while Apache has it open.

```bash
sudo rm /var/log/apache2/reports-access.log
df -h /var/log
sudo lsof +L1 | grep -E "COMMAND|apache2"
```

Sample line:

```text
apache2 8557     root   13w   REG  0,661 314827800     0 668615 /var/log/apache2/reports-access.log (deleted)
```

- The file is gone from `ls`, but `df` still shows the space used.
- `lsof +L1` lists files that are deleted but still **open**: Apache still holds it, so Linux cannot free the space.

**Fix and verify**

```bash
sudo systemctl reload apache2
curl -s -o /dev/null http://localhost:8090/
sleep 5
sudo lsof +L1 | grep -c apache2
df -h /var/log
ls -l /var/log/apache2/reports-access.log
```

- The reload makes Apache close the old file and open a new one; the curl writes the first line into it.
- `grep -c` prints `0` once the old workers have finished (a few seconds): nobody holds the deleted file, the space comes back.
- The safe way to empty a log that is open: `sudo truncate -s 0 <file>` (keeps the file, frees the space at once).
- Long-term: logrotate (topic 13.7) and an alert on `df`.

## Scenario 12 · All workers busy: AH00484

- Do topic 14.5 again: shrink to 10 workers, send 30 slow requests.

**Evidence**

```bash
sudo grep AH00484 /var/log/apache2/error.log | tail -n 1
curl -s "http://localhost/server-status?auto" | grep -E "BusyWorkers|IdleWorkers|Scoreboard"
```

- `AH00484: server reached MaxRequestWorkers setting`, scoreboard full of `W`, even static pages wait.
- **Fix:** restore `mpm_event.conf.bak` and restart; then find **why** requests were slow (Scenario 10).

## Scenario 13 · A module switched off, Apache will not start

**Break it**

```bash
sudo a2dismod headers
sudo apache2ctl configtest
```

Sample line:

```text
AH00526: Syntax error on line 59 of /etc/apache2/conf-enabled/security.conf:
Invalid command 'Header', perhaps misspelled or defined by a module not included in the server configuration
```

- `Header` is spelled correctly: the **module** that provides it (`headers`) is off.
- Same message as a typo. Tell them apart: check the spelling, then `apache2ctl -M | grep headers`.

**Fix and verify**

```bash
sudo a2enmod headers
sudo apache2ctl configtest && sudo systemctl restart apache2
sudo apache2ctl -M | grep headers
```

---

## Quick map: symptom → first command

| Symptom | First command | Look for |
|---|---|---|
| `Couldn't connect to server` | `systemctl status apache2`, `journalctl -u apache2 -n 20` | `AH00526`, `AH00072`, `no listening sockets` |
| timeout from laptop only | `sudo ufw status` | missing allow rule |
| 403 | `tail` site error log | `AH01630` rule · `AH01276` listing · `(13) AH00132/AH00035` permissions |
| 401 forever | `tail` error log | `AH01617` / `AH01618` / `AH01620` |
| 404 "but it's there" | `apache2ctl -S`, configtest warnings | `AH00112` DocumentRoot, wrong site |
| 500 | `tail` error log | `.htaccess: Invalid command`, `AH01620` |
| wrong page, 200 | `apache2ctl -S` | ServerName / ServerAlias |
| too many redirects | `curl -sI`, access log | same path with 301/302 again and again |
| slow | `%D` in access log, server-status | slow URL vs `AH00484` |
| disk full | `df -h`, `du -sh … \| sort -h`, `lsof +L1` | big or deleted-open logs |
