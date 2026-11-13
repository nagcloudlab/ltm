# 11 · Lab 2: Two websites, three faults, two fixes

**Time:** 35 min · **Work:** in pairs · **Use:** only commands from topics 01–10

Do every step. Write the answer or the evidence line in the last column. For each fault, say **which log or command told you the cause**.

**Start clean:** make sure `portal` (from topic 05) works:

```bash
curl -s -H "Host: portal.example.com" http://localhost/ | head -n 3
```

---

## Steps

| # | Task | Do | Your evidence |
|---|---|---|---|
| 1 | **Prove Apache is healthy** | status · port · answer | |
| 2 | **Add a second site: `admin2`** | folder `/var/www/admin2`, page, `admin2.conf` with `ServerName admin2.example.com` and its own logs, `a2ensite` | |
| 3 | **Test, reload, verify** | configtest → reload → curl with the Host header | |
| 4 | **Read the site map and both logs** | `apache2ctl -S` · `tail` admin2's access log | |
| 5 | **Break it: 404** | ask admin2 for `/missing.html` | access-log line: |
| 6 | **Break it: 403** | `chmod 700` on `/var/www/admin2` → curl → error log → `chmod 755` | error-log code: |
| 7 | **Break it: typo** | write `DocumentRot` in admin2.conf → configtest → fix | configtest line: |
| 8 | **Listings: see the leak, then close it** | `/var/www/admin2/files/` with two files and no index → 403 (listings are off server-wide since topic 04) → switch them on for admin2 → see the files → switch off → 403 | error-log code: |
| 9 | **Count and hide** | status counts of admin2's log · hide the version · prove both | |

---

## Commands you will need (in order)

### 1

```bash
systemctl status apache2 --no-pager
sudo ss -lntp | grep ':80 '
curl -I http://localhost/
```

### 2

```bash
sudo mkdir -p /var/www/admin2
echo "<h1>Admin 2</h1>" | sudo tee /var/www/admin2/index.html
sudo vi /etc/apache2/sites-available/admin2.conf
```

```apache
<VirtualHost *:80>
    ServerName admin2.example.com
    DocumentRoot /var/www/admin2
    ErrorLog ${APACHE_LOG_DIR}/admin2-error.log
    CustomLog ${APACHE_LOG_DIR}/admin2-access.log combined
</VirtualHost>
```

```bash
sudo a2ensite admin2
```

### 3

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -H "Host: admin2.example.com" http://localhost/
```

### 4

```bash
sudo apache2ctl -S
sudo tail -n 3 /var/log/apache2/admin2-access.log
```

### 5

```bash
curl -I -H "Host: admin2.example.com" http://localhost/missing.html
sudo tail -n 1 /var/log/apache2/admin2-access.log
```

### 6

```bash
sudo chmod 700 /var/www/admin2
curl -I -H "Host: admin2.example.com" http://localhost/
sudo tail -n 1 /var/log/apache2/admin2-error.log
sudo chmod 755 /var/www/admin2
```

### 7

```bash
sudo cp /etc/apache2/sites-available/admin2.conf /etc/apache2/sites-available/admin2.conf.bak
sudo sed -i 's/DocumentRoot/DocumentRot/' /etc/apache2/sites-available/admin2.conf
sudo apache2ctl configtest
sudo cp /etc/apache2/sites-available/admin2.conf.bak /etc/apache2/sites-available/admin2.conf
sudo apache2ctl configtest
```

### 8

```bash
sudo mkdir -p /var/www/admin2/files
sudo touch /var/www/admin2/files/report.pdf /var/www/admin2/files/db.sql
curl -I -H "Host: admin2.example.com" http://localhost/files/
sudo tail -n 1 /var/log/apache2/admin2-error.log
```

- 403: `Options -Indexes` in `apache2.conf` (topic 04.10) already protects every folder under `/var/www`.

Now see what a leak looks like. Add to admin2.conf, inside the VirtualHost:

```apache
    <Directory /var/www/admin2>
        Options +Indexes
    </Directory>
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -s -H "Host: admin2.example.com" http://localhost/files/ | grep -o 'href="[^"]*"'
```

- Anyone can now see `report.pdf` and `db.sql`. Change `+Indexes` to `-Indexes` in admin2.conf, then:

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -I -H "Host: admin2.example.com" http://localhost/files/
```

### 9

```bash
sudo cut -d' ' -f9 /var/log/apache2/admin2-access.log | sort | uniq -c | sort -rn
grep -n -E "^(ServerTokens|ServerSignature)" /etc/apache2/conf-available/security.conf
curl -sI -H "Host: admin2.example.com" http://localhost/ | grep Server
```

- If the version is still visible, set `ServerTokens Prod` and `ServerSignature Off` as in topic 07, configtest, reload, check again.)

---

## Fast finishers

1. Give admin2 a password (`Require valid-user`) and prove 401 → 200.
2. Add `%D` to admin2's log format and find its slowest request.
3. Move admin2 to port 8090 as a port-based site and back.

---

## Trainer answer key

| # | Expected evidence |
|---|---|
| 1 | `active (running)`; `LISTEN 0.0.0.0:80 … apache2`; `HTTP/1.1 200 OK` |
| 2–3 | `<h1>Admin 2</h1>` returned for `Host: admin2.example.com` |
| 4 | `-S` lists `port 80 namevhost admin2.example.com (…/admin2.conf:1)`; access-log lines with status 200 |
| 5 | `HTTP/1.1 404 Not Found`; access log `"GET /missing.html HTTP/1.1" 404` |
| 6 | `403 Forbidden`; error log `(13)Permission denied: … AH00035: access to /index.htm denied (filesystem path '/var/www/admin2/index.htm') because search permissions are missing on a component of the path` |
| 7 | `AH00526: Syntax error on line 3 of /etc/apache2/sites-enabled/admin2.conf: Invalid command 'DocumentRot', perhaps misspelled …`; then `Syntax OK` |
| 8 | first `403` + `AH01276: Cannot serve directory /var/www/admin2/files/: No matching DirectoryIndex … forbidden by Options directive`; with `+Indexes` the hrefs `report.pdf` and `db.sql`; after `-Indexes` `403` again |
| 9 | counts of 200, 403, 404 (403 appears several times: steps 6 and 8); `Server: Apache` with no version (already set in topic 07) |
