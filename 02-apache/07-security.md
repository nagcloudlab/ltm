# 07 · Security: passwords, .htaccess, hidden files, headers, hiding the version

**Time:** 45 min

**You will learn:** password-protect a folder (code **401**), add users, `.htaccess` files and `AllowOverride`, a broken `.htaccess` (code **500**), restrict by IP, block hidden and backup files, security headers, hide the Apache version, and what not to do.

---

## 07.1 · 401 vs 403

```
1 visitor: GET /admin/          →  2 Apache: 401 "who are you?"
3 browser shows a login box     →  4 right password: 200 · wrong: 401 again
```

| Code | Means |
|---|---|
| **401 Unauthorized** | I don't know who you are yet: log in |
| **403 Forbidden** | I know (or don't care), and the answer is no |

> Basic authentication sends the password **encoded, not encrypted**. Use it only over https (topic 12) or inside the company network.

## 07.2 · Step 1: the password file

`htpasswd` comes with Apache (package `apache2-utils`).

```bash
sudo htpasswd -c /etc/apache2/.htpasswd admin
sudo htpasswd /etc/apache2/.htpasswd ops
sudo cat /etc/apache2/.htpasswd
```

| Option | Means |
|---|---|
| `-c` | **create** the file (and overwrite an existing one!) |
| no `-c` | add or change a user in an existing file |
| `-D user` | delete a user |

> Use `-c` only for the **first** user. `-c` on the second wipes the first.

Keep the file **outside** web folders (`/etc/apache2/`) so nobody can download it. The lines are `user:$apr1$…`: hashed, not plain passwords.

## 07.3 · Step 2: protect the folder

```bash
sudo mkdir -p /var/www/html/admin
echo "<h1>Admin area</h1>" | sudo tee /var/www/html/admin/index.html
sudo vi /etc/apache2/sites-available/000-default.conf
```

Inside the VirtualHost:

```apache
    <Directory /var/www/html/admin>
        AuthType Basic
        AuthName "Admins only"
        AuthUserFile /etc/apache2/.htpasswd
        Require valid-user
    </Directory>
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -I http://localhost/admin/
curl -u admin:yourpassword -I http://localhost/admin/
curl -u admin:wrong -I http://localhost/admin/
sudo tail -n 2 /var/log/apache2/error.log
```

| Line | Means |
|---|---|
| `AuthType Basic` | user name + password box |
| `AuthName` | text shown in the box (the "realm") |
| `AuthUserFile` | where the users are |
| `Require valid-user` | any user in the file; `Require user admin` = only admin |

Sample lines (error.log):

```text
[Thu Nov 12 21:11:37.992236 2026] [auth_basic:error] [pid 5270:tid 281473626075424] [client 127.0.0.1:34218] AH01617: user admin: authentication failure for "/admin/": Password Mismatch
[Thu Nov 12 21:11:37.995304 2026] [auth_basic:error] [pid 5270:tid 281473609167136] [client 127.0.0.1:34232] AH01618: user nobody not found: /admin/
```

- `AH01617 … Password Mismatch` = right user, wrong password.
- `AH01618 user … not found` = the user is not in `.htpasswd`.
- The first 401 (no password sent at all) writes **nothing** in error.log: that is normal, the browser simply shows the login box.
- The access log shows the user name in field 3 even when the login failed (`127.0.0.1 - admin [...] "HEAD /admin/ HTTP/1.1" 401`).
- Security teams watch these lines for password guessing.

In the laptop browser, `http://[vm-ip]/admin/` shows the login box.

## 07.4 · Password **and** office network only

```apache
    <Directory /var/www/html/admin>
        AuthType Basic
        AuthName "Admins only"
        AuthUserFile /etc/apache2/.htpasswd
        <RequireAll>
            Require valid-user
            Require ip 10.0.0.0/24 127.0.0.1
        </RequireAll>
    </Directory>
```

| Block | Means |
|---|---|
| `<RequireAll>` | **every** line must be true |
| `<RequireAny>` | **one** line is enough |

## 07.5 · .htaccess: settings inside a web folder

A `.htaccess` file holds config lines **in the folder itself**. Apache reads it on **every request**, only if the folder allows it with `AllowOverride`.

```
GET /blog/post.html  →  /var/www/html/blog/.htaccess (read first)  →  answer
```

```bash
sudo mkdir -p /var/www/html/blog
echo "<h1>Blog</h1>" | sudo tee /var/www/html/blog/index.html
echo "Redirect temp /blog/old.html /blog/" | sudo tee /var/www/html/blog/.htaccess
curl -I http://localhost/blog/old.html
```

404: Ubuntu's default `AllowOverride None` **ignores** `.htaccess`. Allow it for this folder only (VirtualHost):

```apache
    <Directory /var/www/html/blog>
        AllowOverride All
    </Directory>
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -I http://localhost/blog/old.html
```

Now 302. Changes to `.htaccess` work **immediately, without reload**.

| AllowOverride | Effect |
|---|---|
| `None` | ignore .htaccess (Ubuntu default; faster; all rules stay in /etc) |
| `All` | obey everything in it |
| `AuthConfig` | only allow password lines |

Some applications ship a `.htaccess` and need it. Otherwise prefer `None`: Apache checks for the file on every request, and rules end up scattered where developers can change them.

## 07.6 · A broken .htaccess: the code 500

**Break it:**

```bash
echo "Redirekt temp /x /blog/" | sudo tee -a /var/www/html/blog/.htaccess
curl -I http://localhost/blog/
sudo tail -n 1 /var/log/apache2/error.log
sudo apache2ctl configtest
```

| What you see | Means |
|---|---|
| **500 Internal Server Error** | the server failed on a valid request: "my side, not yours" |
| error log: `[core:alert] … /var/www/html/blog/.htaccess: Invalid command 'Redirekt', perhaps misspelled …` | the exact file and word |
| `configtest` says **Syntax OK** | configtest does **not** read .htaccess files |

Fix: remove the bad line (no reload needed).

```bash
sudo sed -i '/Redirekt/d' /var/www/html/blog/.htaccess
curl -I http://localhost/blog/
```

## 07.7 · Block hidden and backup files

Developers leave `.env`, `.git/`, `config.php.bak` in web folders. Ubuntu already blocks `.ht*` files:

```bash
grep -n -A2 "FilesMatch" /etc/apache2/apache2.conf
```

Block all hidden files and backups (VirtualHost):

```apache
    <FilesMatch "^\.">
        Require all denied
    </FilesMatch>
    <FilesMatch "\.(bak|old|swp|sql|tar|gz|zip)$">
        Require all denied
    </FilesMatch>
    RedirectMatch 404 /\.git
```

```bash
echo "DB_PASSWORD=secret" | sudo tee /var/www/html/.env
sudo touch /var/www/html/index.html.bak
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -I http://localhost/.env
curl -I http://localhost/index.html.bak
sudo rm /var/www/html/.env /var/www/html/index.html.bak
```

Both 403. In real access logs, bots probe for `/.env`, `/.git/config` and `/wp-login.php` all day.

## 07.8 · Security headers

Needs `mod_headers` (enabled in topic 06). Server-wide, in `/etc/apache2/conf-available/security.conf`:

```apache
Header always set X-Content-Type-Options "nosniff"
Header always set X-Frame-Options "SAMEORIGIN"
Header always set Referrer-Policy "strict-origin-when-cross-origin"
```

```bash
sudo cp /etc/apache2/conf-available/security.conf /etc/apache2/conf-available/security.conf.bak
sudo vi /etc/apache2/conf-available/security.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -sI http://localhost/ | grep -E "X-|Referrer"
```

| Header | Stops |
|---|---|
| `X-Content-Type-Options: nosniff` | browsers guessing a file type and running it as script |
| `X-Frame-Options: SAMEORIGIN` | other sites showing your pages inside a frame (click-jacking) |
| `Referrer-Policy` | leaking full URLs to other sites |

`Strict-Transport-Security` (forcing https) comes in topic 12 with certificates.

## 07.9 · Don't tell attackers your version

```bash
curl -sI http://localhost/ | grep Server
grep -n -E "^(ServerTokens|ServerSignature)" /etc/apache2/conf-available/security.conf
```

In `security.conf` set:

```apache
ServerTokens Prod
ServerSignature Off
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -sI http://localhost/ | grep Server
```

| Before | After |
|---|---|
| `Server: Apache/2.4.58 (Ubuntu)` | `Server: Apache` |

It fixes no bug, but stops advertising exactly which bugs to try. Security audits check for it.

## 07.10 · Security checklist

| Check | How |
|---|---|
| no folder listings | `grep -n "Options" /etc/apache2/apache2.conf` has `-Indexes` |
| version hidden | `curl -sI` shows `Server: Apache` |
| hidden/backup files blocked | `curl -I /.env` → 403 |
| only needed modules | `apache2ctl -M` |
| status page private | `Require local` in status.conf |
| files root-owned, 644/755 | `ls -l /var/www/…` |
| passwords only over https | topic 12 |
| firewall: only 22, 80, 443 | `sudo ufw status` |

---

## Exercises

1. Add a user `auditor`, then allow **only** `auditor` into `/admin/`.
2. Protect `/blog/` with a password using **only** a `.htaccess` file. What must `AllowOverride` allow?
3. Make `/admin/` reachable from the office network **or** with a password (either is enough).
4. A developer's `.htaccess` change made the whole folder return 500, but `configtest` says Syntax OK. Explain, and say where to look.
5. Prove the version is hidden on the 404 error page too.

## Answers

1. `sudo htpasswd /etc/apache2/.htpasswd auditor` (no `-c`); `Require user auditor`.
2. Put the four `Auth…`/`Require` lines in `/var/www/html/blog/.htaccess`; the folder needs `AllowOverride AuthConfig` (or `All`).
3. `<RequireAny> Require ip 10.0.0.0/24  Require valid-user </RequireAny>` with the Auth lines.
4. configtest checks only files under `/etc/apache2`; `.htaccess` is read per request. The error log names the `.htaccess` file and the bad line.
5. `curl -s http://localhost/nothing.html` (with the default error page): no `Apache/2.4.58` line at the bottom (`ServerSignature Off`).
