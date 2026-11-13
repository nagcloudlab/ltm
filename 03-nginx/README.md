# 03 · Nginx · Hands-on handout

A detailed lab handout for the Nginx web server on your own **Ubuntu 24.04** lab VM. One topic per file, in teaching order. Read the explanation, type the commands, do the exercises.

**Before you start:** finish `01-linux` and `02-apache`. Nginx does the same job as Apache with different words, so each topic shows the Apache equivalent. **Apache keeps ports 80 and 8090**; Nginx runs on **8081**, **8082**, **8083** (practice site) and **8443** (HTTPS).

- Topics 01–09: the core, in order. Lab 3 closes it.
- Topics 10–15: advanced. Do them in order too: 11 creates the `lab` site that 12, 14 and 15 use.
- Tested on Ubuntu 24.04 with Nginx 1.24.0.

---

## Topics

| # | File | Topic | Time |
|---|---|---|---|
| 01 | [01-install-and-service.md](01-install-and-service.md) | install (and the port-80 clash), master and workers, start/stop/reload, `nginx -t` | 35 min |
| 02 | [02-config-files.md](02-config-files.md) | `/etc/nginx`, contexts and blocks, `nginx.conf` line by line, `nginx -T`, Apache → Nginx words | 35 min |
| 03 | [03-server-blocks.md](03-server-blocks.md) | websites: `listen`, `server_name`, `default_server`, by name and by port | 40 min |
| 04 | [04-locations-and-files.md](04-locations-and-files.md) | `location` matching, `root` vs `alias`, `try_files`, `index`, `autoindex`, redirects, error pages | 50 min |
| 05 | [05-access-and-security.md](05-access-and-security.md) | allow/deny, passwords (401), hidden files, headers, `server_tokens`, upload size (413), rate limiting | 45 min |
| 06 | [06-logs.md](06-logs.md) | access and error logs, custom formats with `$request_time`, per-site logs, analysis, rotation | 40 min |
| 07 | [07-performance.md](07-performance.md) | workers × connections, keepalive, gzip, browser caching, `stub_status`, load testing | 40 min |
| 08 | [08-troubleshooting.md](08-troubleshooting.md) | port taken, missing `;`, warnings, 403 × 2, 404 from `root`/`alias`, 405, 413, wrong site | 45 min |
| 09 | [09-lab3-nginx.md](09-lab3-nginx.md) | **Lab 3:** two web servers side by side | 30 min |
| | **Advanced** | | |
| 10 | [10-https.md](10-https.md) | self-signed certificate, HTTPS on 8443, HTTP/2, TLS versions, `openssl s_client`, TLS errors | 45 min |
| 11 | [11-redirects-and-rewrites.md](11-redirects-and-rewrites.md) | `return` vs `rewrite`, flags, query strings, 301 loop, rewrite cycle (500), `rewrite_log` | 40 min |
| 12 | [12-advanced-logging.md](12-advanced-logging.md) | JSON logs, errors-only log, log levels, which log gets what, `mv` + `nginx -s reopen` | 40 min |
| 13 | [13-capacity-tuning.md](13-capacity-tuning.md) | workers × connections, open-file limits, `Too many open files`, `worker_rlimit_nofile`, `open_file_cache` | 45 min |
| 14 | [14-troubleshooting-scenarios.md](14-troubleshooting-scenarios.md) | ten break → read → fix → verify scenarios | 90 min |
| 15 | [15-reading-logs-drills.md](15-reading-logs-drills.md) | access and error log anatomy, 12 drill questions with exact answers | 45 min |
| 99 | [99-cheatsheet.md](99-cheatsheet.md) | one-page reference, with Apache equivalents | |

---

## How to use the files

- **Command blocks contain only commands.** Copy and paste them, or type them.
- Blocks marked `nginx` are **config lines** to type into a file with `sudo vi`.
- **Every Nginx line ends with `;`** and every block closes with `}`. Most Nginx errors are a missing `;`.
- Change routine, every time: `sudo cp f f.bak` → `sudo vi f` → `sudo nginx -t && sudo systemctl reload nginx` → `curl`.
- **Reload vs restart:** a reload that fails (bad config, port taken) keeps the old config running and writes the reason to `/var/log/nginx/error.log`. Changing a `listen` **address** on the same port needs a `restart`.
- Lines shown under **Sample line** are what you should see, for reading practice. They are never commands.
- **Break it** steps are deliberate mistakes. Do them, read the error, then fix.
- Each topic ends with **Exercises** and **Answers**.

### Names used everywhere

| Item | Value |
|---|---|
| Apache | port **80** (from `02-apache`, leave it running) |
| Nginx sites | `shop` on **8081** (default), `blog.example.com` on 8081 by name, `stats` on **8082**, `lab.example.com` on **8083**, `shop-ssl` on **8443** |
| folders | `/var/www/shop`, `/var/www/blog`, `/var/www/stats`, `/var/www/lab`, `/srv/manuals`, `/srv/labfiles` |
| hosts file | `127.0.0.1 shop.example.com blog.example.com www.blog.example.com lab.example.com` |
| your VM | `[vm-ip]` (find it with `ip addr`) |

### Reset a broken Nginx completely

```bash
sudo apt purge -y nginx nginx-common nginx-core
sudo rm -rf /etc/nginx /var/www/shop /var/www/blog /var/www/stats /var/www/lab /var/www/promo /srv/manuals /srv/labfiles
sudo apt install -y nginx
```

- Port 80 still belongs to Apache, so the fresh install does not start: repeat 01.3 and 01.4 (remove the default site link, start Nginx).
