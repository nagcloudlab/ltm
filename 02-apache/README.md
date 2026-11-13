# 02 · Apache HTTP Server · Hands-on handout

A detailed lab handout for the Apache web server on your own **Ubuntu 24.04** lab VM. One topic per file, in teaching order. Read the explanation, type the commands, do the exercises.

**Before you start:** finish the Linux handout (`01-linux`), especially processes, services, logs, grep, network and permissions. Apache uses all of them.

---

## Topics

| # | File | Topic | Time |
|---|---|---|---|
| 01 | [01-http-basics.md](01-http-basics.md) | HTTP: requests, responses, methods, headers, status codes, URLs | 35 min |
| 02 | [02-install-and-service.md](02-install-and-service.md) | install, prove it works, start/stop/reload, auto-start, firewall | 35 min |
| 03 | [03-config-files.md](03-config-files.md) | `/etc/apache2`, how config is read, parent and workers, ports, timeouts | 40 min |
| 04 | [04-pages-and-folders.md](04-pages-and-folders.md) | DocumentRoot, your first site, `<Directory>`, Require, listings, Alias, ownership | 45 min |
| 05 | [05-virtual-hosts.md](05-virtual-hosts.md) | many websites on one server: by name and by port | 45 min |
| 06 | [06-safe-changes-and-features.md](06-safe-changes-and-features.md) | configtest habit, redirects, rewrite, error pages, modules, status page | 40 min |
| 07 | [07-security.md](07-security.md) | passwords (401), `.htaccess` (500), hidden files, headers, hiding the version | 45 min |
| 08 | [08-logs.md](08-logs.md) | access and error logs, every field, analysis one-liners, response time, rotation | 45 min |
| 09 | [09-performance.md](09-performance.md) | workers (MPM), KeepAlive, compression, browser caching, load testing | 40 min |
| 10 | [10-troubleshooting.md](10-troubleshooting.md) | won't start, port taken, typo, 403 × 2, 404, 500, timeout from laptop | 45 min |
| 11 | [11-lab2-two-websites.md](11-lab2-two-websites.md) | **Lab 2:** two websites, three faults, two fixes | 35 min |
| 12 | [12-https.md](12-https.md) | **Advanced:** self-signed certificate, mod_ssl, port 443, curl `-k`/`--cacert`, TLS errors, http→https, HSTS | 50 min |
| 13 | [13-advanced-logging.md](13-advanced-logging.md) | **Advanced:** own LogFormat (`%D`, Host, X-Forwarded-For), a slow page, shared vhost log, rewrite trace, rotation | 50 min |
| 14 | [14-status-and-tuning.md](14-status-and-tuning.md) | **Advanced:** full status page, scoreboard letters, event MPM numbers, filling every worker (AH00484) | 50 min |
| 15 | [15-troubleshooting-scenarios.md](15-troubleshooting-scenarios.md) | **Scenarios:** 13 failures, each: break → symptom → log line → cause → fix → verify | 90 min |
| 16 | [16-log-reading-drills.md](16-log-reading-drills.md) | **Drills:** read one hour of access and error log, 15 questions with checked answers | 60 min |
| 99 | [99-cheatsheet.md](99-cheatsheet.md) | one-page reference | |
| — | [make-apache-sample-logs.sh](make-apache-sample-logs.sh) | creates `~/lab/apache/access.log` and `error.log` for topic 16 | |

- Topics 01–11 are the core course, in order.
- Topics 12–14 go deeper; each uses the sites built in 05 and the slow page from 13.
- Topics 15–16 are practice: do them after 01–11 (15 also uses 13). 16 needs nothing but the script.

---

## How to use the files

- **Command blocks contain only commands.** Copy and paste them, or type them (typing is better for learning).
- Text after `#` is a comment; bash ignores it, so it is safe to paste.
- Blocks marked `apache` are **config lines** to type into a file with `sudo vi`, not commands.
- Blocks marked `text` and introduced as **Sample line** show what a log or command prints. Do not paste them; compare them with yours.
- Your output will differ from your neighbour's (PIDs, times, IPs). Read the explanation table under each block.
- **Always back up a config file before editing it:** `sudo cp file file.bak`.
- **Break it** steps are deliberate mistakes. Do them, read the error, then fix.
- Each topic ends with **Exercises** and **Answers**.

### Names used everywhere

| Item | Value |
|---|---|
| your VM | `[vm-ip]`, e.g. `10.0.0.5` (find it with `ip addr`) |
| web folders | `/var/www/html` (default), `/var/www/portal`, `/var/www/admin` |
| website names | `portal.example.com`, `admin.example.com` |
| ports | **80** Apache · **443** Apache https (topic 12) · **8090** Apache port-based exercise · 8080 reserved for Tomcat · 8081 reserved for Nginx |

### Reset a broken Apache completely

```bash
sudo apt purge -y apache2 apache2-utils apache2-bin apache2-data
sudo rm -rf /etc/apache2 /var/www/portal /var/www/admin
sudo apt install -y apache2
```
