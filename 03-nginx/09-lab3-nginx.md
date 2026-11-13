# 09 · Lab 3: Two web servers side by side

**Time:** 30 min · **Work:** in pairs · **Use:** commands from `02-apache` and topics 01–08 here

Apache on **80**, Nginx on **8081**. Do every step and write the evidence.

---

## Steps

| # | Task | Your evidence |
|---|---|---|
| 1 | **Both healthy?** status of both services, both ports in `ss` | |
| 2 | **Ask each one** `curl -I` on 80 and 8081 | |
| 3 | **Which one answered?** read the `Server:` header of each | |
| 4 | **Break it: 404** ask Nginx for `/sale.png`, find the error-log line | |
| 5 | **Break it: missing `;`** delete one `;` in the shop file, `nginx -t`, fix | |
| 6 | **Lock a path** `location /admin/ { deny all; }` → curl → 403 → error-log line | |
| 7 | **Count and hide** status counts of `shop-access.log` · `server_tokens off;` · prove it | |
| 8 | **Compare** `ab -n 2000 -c 50` against both; note requests per second | |

---

## Commands (in order)

### 1

```bash
systemctl is-active apache2 nginx
sudo ss -lntp | grep -E "apache2|nginx"
```

### 2–3

```bash
curl -I http://localhost/
curl -I http://localhost:8081/
curl -sI http://localhost/ | grep -i server
curl -sI http://localhost:8081/ | grep -i server
```

### 4

```bash
curl -I http://localhost:8081/sale.png
sudo tail -n 1 /var/log/nginx/shop-error.log
```

### 5

```bash
sudo cp /etc/nginx/sites-available/shop /etc/nginx/sites-available/shop.bak
sudo vi /etc/nginx/sites-available/shop
sudo nginx -t
sudo cp /etc/nginx/sites-available/shop.bak /etc/nginx/sites-available/shop
sudo nginx -t && sudo systemctl reload nginx
```

### 6

```nginx
    location /admin/ {
        deny all;
    }
```

(Replace the existing `/admin/` location for this step; put the password version back afterwards.)

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -I http://localhost:8081/admin/
sudo tail -n 1 /var/log/nginx/shop-error.log
```

### 7

```bash
sudo cut -d' ' -f9 /var/log/nginx/shop-access.log | sort | uniq -c | sort -rn
grep -n server_tokens /etc/nginx/nginx.conf
curl -sI http://localhost:8081/ | grep -i server
```

### 8

```bash
ab -n 2000 -c 50 http://localhost/ | grep "Requests per second"
ab -n 2000 -c 50 http://localhost:8081/ | grep "Requests per second"
```

---

## Fast finishers

1. Add `blog.example.com` on Nginx **and** a `blog.example.com` site on Apache. Which one answers `http://blog.example.com/` and which `http://blog.example.com:8081/`? Why?
2. Make Nginx's `/nginx_status` and Apache's `/server-status` both reachable only from the server, and compare their numbers during an `ab` run.

---

## Trainer answer key

| # | Expected evidence |
|---|---|
| 1 | `active` `active`; `0.0.0.0:80` and `0.0.0.0:8090 … apache2`; `0.0.0.0:8081` and `0.0.0.0:8082 … nginx` (plus `8443` after topic 10) |
| 2–3 | `Server: Apache` on 80; `Server: nginx` (or `nginx/1.24.0 (Ubuntu)` before step 7) on 8081 |
| 4 | `404`; `open() "/var/www/shop/sale.png" failed (2: No such file or directory)` (a `.png` uses the caching location without try_files, so the miss is logged; `/sale.html` would show only in the access log) |
| 5 | `[emerg] … not terminated by ";"` or `unexpected …` with file and line; then `test is successful` |
| 6 | `403`; `access forbidden by rule, client: 127.0.0.1` |
| 7 | counts of 200/301/403/404/405…; `Server: nginx` with no version |
| 8 | both high for a tiny static page; differences grow with concurrency |
| FF 1 | port 80 → Apache's blog (only Apache listens on 80); 8081 → Nginx's blog. The port decides the server, then the Host header decides the site |
