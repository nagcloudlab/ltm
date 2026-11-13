# 01 · Install Nginx and manage the service

**Time:** 35 min

**You will learn:** what makes Nginx different, install it next to Apache (and fix the port clash), the master and worker processes, the three health checks, start/stop/reload, `nginx -t`, and `nginx -s`.

---

## 01.1 · Nginx in one picture

```text
Classic Apache:  one worker per visitor        table 1 ← waiter A    table 2 ← waiter B    table 3 waits…
Nginx:           one worker per CPU core       one fast waiter serves whichever table is ready, never stands and waits
```

| | Apache | Nginx (say "engine-x") |
|---|---|---|
| job | listen, pick site, send file, log | the same |
| design | a worker (thread) per request | a few workers, each handling **thousands** of connections (event loop) |
| strong at | `.htaccess`, many modules, classic sites | busy front doors, static files, reverse proxy |
| config | `<VirtualHost>`, `<Directory>` | `server { }`, `location { }` |
| per-folder files | `.htaccess` | none: all config in `/etc/nginx` |

## 01.2 · Before: who owns port 80?

```bash
sudo ss -lntp | grep ':80 '
systemctl is-active apache2
```

Apache (from `02-apache`) owns port 80. Nginx's default site also wants port 80.

## 01.3 · Install… and it fails to start

```bash
sudo apt update
sudo apt install -y nginx
```

- apt finishes the install, but Nginx does **not** start.
- Near the end apt prints `Not attempting to start NGINX, port 80 is already in use.` (you may also see `Could not execute systemctl`).
- Find out why:

```bash
systemctl status nginx --no-pager
journalctl -u nginx -n 10 --no-pager
sudo ss -lntp 'sport = :80'
```

| Evidence | Means |
|---|---|
| `Active: failed` | Nginx is not running |
| `bind() to 0.0.0.0:80 failed (98: Address already in use)` | port 80 is taken |
| `ss` shows `apache2` on :80 | Apache owns it |

**Decision:** Apache keeps 80. Nginx's default site goes; our own site will use 8081.

## 01.4 · Remove the default site's link, start Nginx

```bash
ls -l /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl start nginx
systemctl status nginx --no-pager
```

`rm` removed only the **link**; the file stays in `sites-available/default`. Nginx now starts but listens on **nothing** yet (no sites):

```bash
sudo ss -lntp | grep nginx
```

## 01.5 · A first site on port 8081

```bash
sudo mkdir -p /var/www/shop
echo "<h1>Shop home</h1><p>served by Nginx</p>" | sudo tee /var/www/shop/index.html
sudo vi /etc/nginx/sites-available/shop
```

```nginx
server {
    listen 8081 default_server;
    server_name shop.example.com;
    root /var/www/shop;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    access_log /var/log/nginx/shop-access.log;
    error_log  /var/log/nginx/shop-error.log;
}
```

```bash
sudo ln -s /etc/nginx/sites-available/shop /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
curl -i http://localhost:8081/
```

Topic 03 explains every line. Nginx has no `a2ensite`: you create the link yourself with `ln -s`.

## 01.6 · Three checks prove it works

```bash
systemctl status nginx --no-pager
sudo ss -lntp | grep nginx
curl -I http://localhost:8081/
```

Compare both servers side by side:

```bash
sudo ss -lntp | grep -E "apache2|nginx"
curl -sI http://localhost/ | grep -i server
curl -sI http://localhost:8081/ | grep -i server
```

The `Server:` header tells you **which product answered**: `Apache` on 80, `nginx/1.24.0 (Ubuntu)` on 8081.

From your laptop: `http://[vm-ip]:8081/` (if ufw is on: `sudo ufw allow 8081/tcp`).

## 01.7 · A team: one master, a few workers

```bash
ps -ef | grep [n]ginx
nproc
cat /run/nginx.pid
```

| | Master | Worker |
|---|---|---|
| runs as | `root` | `www-data` |
| job | read config, open ports, start and watch workers | serve visitors, thousands each |
| how many | one | one per CPU core (`worker_processes auto`) |

Same idea as Apache's parent and workers; the difference is how much one worker can handle.

## 01.8 · Service life cycle

```bash
sudo systemctl stop nginx
curl -I http://localhost:8081/
sudo systemctl start nginx
curl -I http://localhost:8081/
sudo systemctl reload nginx
sudo systemctl restart nginx
systemctl is-enabled nginx
```

| | `reload` | `restart` |
|---|---|---|
| does | master re-reads config, starts **new** workers, old workers finish their requests | stop everything, then start |
| visitors | not cut off | in-flight requests dropped |
| broken config | old config keeps running | Nginx **does not come back** |

Watch a reload replace the workers:

```bash
ps -ef | grep [n]ginx
sudo systemctl reload nginx
ps -ef | grep [n]ginx
```

The master PID stays the same; the worker PIDs are new.

## 01.9 · nginx -t: test before every reload

```bash
sudo nginx -t
```

**Break it:**

```bash
sudo cp /etc/nginx/sites-available/shop /etc/nginx/sites-available/shop.bak
sudo sed -i 's/root \/var\/www\/shop;/root \/var\/www\/shop/' /etc/nginx/sites-available/shop
sudo nginx -t
sudo systemctl reload nginx
curl -I http://localhost:8081/
```

Sample line from `nginx -t`:

```text
2026/11/12 20:03:15 [emerg] 2597#2597: invalid number of arguments in "root" directive in /etc/nginx/sites-enabled/shop:5
```

- Without the `;`, Nginx joins line 5 and line 6 into one: `root /var/www/shop index index.html;`. Too many words for `root`.
- `nginx -t` names the **file** and the **line**.
- The reload fails, **but the old config keeps serving** (curl still gets 200).

Fix:

```bash
sudo cp /etc/nginx/sites-available/shop.bak /etc/nginx/sites-available/shop
sudo nginx -t && sudo systemctl reload nginx
```

## 01.10 · The nginx command itself

| Command | Does |
|---|---|
| `nginx -t` | test the config |
| `nginx -T` | test and **print** the whole config (topic 02) |
| `nginx -v` / `nginx -V` | version / version + build options and modules |
| `nginx -s reload` | tell the running master to reload (like `systemctl reload`) |
| `nginx -s reopen` | reopen log files (used by log rotation) |
| `nginx -s quit` | graceful stop |

```bash
nginx -v
sudo nginx -V 2>&1 | tr ' ' '\n' | grep -E "status|gzip|realip"
```

On a systemd server prefer `systemctl`; `nginx -s` is useful in containers and scripts.

---

## Exercises

1. Show which program owns port 80 and which owns 8081, in one command.
2. Reload Nginx and prove the workers were replaced but the master was not.
3. Stop Nginx. What does `curl -I http://localhost:8081/` say, and which Linux topic explains it?
4. How many worker processes does your VM run, and why that number?
5. Where is the original default site file now?

## Answers

1. `sudo ss -lntp | grep -E ":80 |:8081 "`.
2. Compare `ps -ef | grep [n]ginx` before and after `sudo systemctl reload nginx`: same master PID, new worker PIDs.
3. `Connection refused`: nothing listens on 8081 (Linux topic 10, refused vs timed out).
4. `ps -ef | grep "[n]ginx: worker" | wc -l` = `nproc`, because `worker_processes auto`.
5. `/etc/nginx/sites-available/default`; only the link in `sites-enabled` was removed.
