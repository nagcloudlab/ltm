# 06 · Safe changes, redirects, error pages, modules, status page

**Time:** 40 min

**You will learn:** the five-step change routine, reload vs restart once more, redirects and the 301 code, `mod_rewrite`, your own error pages, enabling modules, and Apache's live status page.

---

## 06.1 · The change routine (use it every time)

| Step | Command |
|---|---|
| 1 back up | `sudo cp file file.bak` |
| 2 edit | `sudo vi file` |
| 3 test | `sudo apache2ctl configtest` |
| 4 apply | `sudo systemctl reload apache2` |
| 5 verify | `curl -I …` and `sudo tail -n 5 /var/log/apache2/error.log` |

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2 && curl -sI http://localhost/ | head -n 1
```

One line for steps 3–5: each part runs only if the previous one succeeded.

Broke it anyway? Put the backup back:

```bash
sudo cp /etc/apache2/sites-available/000-default.conf.bak /etc/apache2/sites-available/000-default.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
```

## 06.2 · A page moved: Redirect, and the code 301

In `000-default.conf`, inside `<VirtualHost *:80>`:

```apache
    Redirect permanent /old.html /hello.html
    Redirect temp      /sale.html /shop/
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -I http://localhost/old.html
curl -I http://localhost/sale.html
curl -L http://localhost/old.html
```

| Code | Line | Means | Browser remembers? |
|---|---|---|---|
| **301 Moved Permanently** | `Redirect permanent` | moved for good | yes, cached for a long time |
| **302 Found** | `Redirect temp` (or just `Redirect`) | moved for now | no |

The answer carries `Location: http://localhost/hello.html`. `curl -L` follows it like a browser.

> Test with **302** first. A wrong 301 stays in users' browsers even after you fix the server.

## 06.3 · Modules: switching features on

```bash
sudo apache2ctl -M
ls /etc/apache2/mods-enabled/ | head
ls /etc/apache2/mods-available/ | wc -l
```

| Module | Does | Enabled on Ubuntu? |
|---|---|---|
| `dir` | picks index.html | yes |
| `alias` | `Alias` lines | yes |
| `auth_basic` | passwords (topic 07) | yes |
| `status` | status page | yes |
| `deflate` | compression (topic 09) | yes |
| `rewrite` | URL patterns | **no** |
| `headers` | add/change headers (topic 07) | **no** |
| `expires` | browser caching (topic 09) | **no** |
| `ssl` | https (topic 12) | **no** |
| `proxy`, `proxy_http` | pass requests to Tomcat (reverse proxy module) | **no** |

```bash
sudo a2enmod rewrite headers
sudo systemctl restart apache2
sudo apache2ctl -M | grep -E "rewrite|headers"
```

Modules need a **restart**, not a reload (`a2enmod` tells you so). `a2dismod name` switches one off. Enable only what you need.

## 06.4 · mod_rewrite: a whole family of URLs

`Redirect` maps one address. `RewriteRule` maps **patterns**:

```apache
    RewriteEngine On
    RewriteRule ^/shop/old/(.*)$ /shop/$1 [R=301,L]
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -I http://localhost/shop/old/style.css
```

| Part | Means |
|---|---|
| `^/shop/old/` | path starts with `/shop/old/` |
| `(.*)` | capture whatever follows |
| `$1` | put the captured part back |
| `[R=301]` | send a 301 redirect |
| `[L]` | last rule: stop here |

Common uses: force `www`, old URL schemes, http → https (topic 12):

```apache
    RewriteCond %{HTTPS} off
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
```

(Read only for now: there is no certificate yet. Topic 12 adds it.)

## 06.5 · Your own error page

Apache's built-in 404 page shows the version. Replace it:

```bash
echo "<h1>Sorry, that page does not exist</h1><p><a href='/'>Home</a></p>" | sudo tee /var/www/html/404.html
```

In the VirtualHost:

```apache
    ErrorDocument 404 /404.html
    ErrorDocument 403 "Not allowed here."
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -i http://localhost/nothing.html
curl -i http://localhost/private/
```

The status stays **404** (or 403): users see a friendly page, monitoring still sees the error.

## 06.6 · server-status: Apache's live dashboard

```bash
cat /etc/apache2/mods-enabled/status.conf | grep -v -E "^\s*#|^\s*$"
curl "http://localhost/server-status?auto"
```

| Line | Means |
|---|---|
| `Total Accesses` | requests since start |
| `BusyWorkers` | workers serving right now |
| `IdleWorkers` | workers waiting |
| `ReqPerSec` | average requests per second |
| `Scoreboard` | one character per worker slot: `_` waiting, `W` sending, `K` keep-alive, `.` empty slot |

Watch it change while traffic flows (two terminals):

```bash
watch -n 1 "curl -s 'http://localhost/server-status?auto' | grep -E 'Busy|Idle|Total Acc'"
```

```bash
for i in $(seq 1 200); do curl -s -o /dev/null http://localhost/; done
```

`Require local` in `status.conf` keeps the page private. **Never** open it to the internet: it shows versions and client addresses. Press `Ctrl+C` to stop `watch`.

---

## Exercises

1. Redirect `/help` to `/shop/` temporarily and prove the status and Location.
2. Make every URL under `/legacy/` redirect permanently to the same path under `/shop/`.
3. Which module would you enable to set headers, and which command proves it is loaded?
4. Give 403 errors your own HTML page. Does the status code change?
5. How many requests has Apache answered since it started?

## Answers

1. `Redirect temp /help /shop/`; `curl -I http://localhost/help` → `302 Found`, `Location: http://localhost/shop/`.
2. `RewriteRule ^/legacy/(.*)$ /shop/$1 [R=301,L]` (with `RewriteEngine On`).
3. `headers`: `sudo a2enmod headers && sudo systemctl restart apache2; sudo apache2ctl -M | grep headers`.
4. `ErrorDocument 403 /403.html`; no, it stays 403.
5. `curl -s "http://localhost/server-status?auto" | grep "Total Accesses"`.
