# 03 · Where Apache keeps things, and how it reads its config

**Time:** 40 min

**You will learn:** the four places Apache uses, every file in `/etc/apache2`, how one main file pulls in the rest, how to read a config file, the parent and worker processes, `envvars`, which ports are opened, and the timeout settings.

---

## 03.1 · Four places

```bash
ls -ld /etc/apache2 /var/www/html /var/log/apache2
ls -l /var/log/apache2
```

| What | Where |
|---|---|
| settings | `/etc/apache2/` |
| web pages | `/var/www/html/` (and any folder you choose) |
| logs | `/var/log/apache2/` (`access.log`, `error.log`) |
| service · user | `apache2` · workers run as `www-data` |

## 03.2 · Inside /etc/apache2

```bash
ls -l /etc/apache2
ls -F /etc/apache2
```

```
/etc/apache2/
├── apache2.conf       the main file
├── conf-available/    extra settings snippets (e.g. security.conf, servername.conf)
├── conf-enabled/      links to the ones switched on
├── envvars            variables: user, log folder, pid file
├── magic              helps guess file types (leave alone)
├── mods-available/    every installed module
├── mods-enabled/      links to modules switched on
├── ports.conf         which ports to open
├── sites-available/   one file per website
└── sites-enabled/     links to websites switched on
```

## 03.3 · One main file pulls in the rest

Apache reads **only** `apache2.conf`. Its `Include` lines load the others:

```bash
grep -n -E "^(Include|IncludeOptional)" /etc/apache2/apache2.conf
```

```
apache2.conf
 ├── mods-enabled/*.load + *.conf      modules
 ├── ports.conf                        Listen 80
 ├── conf-enabled/*.conf               extra settings
 └── sites-enabled/*.conf              websites
```

Only the **-enabled** folders are loaded. That is how switching things on and off works.

```bash
ls -l /etc/apache2/sites-enabled/
readlink -f /etc/apache2/sites-enabled/000-default.conf
```

`000-default.conf` in sites-enabled is a **symbolic link** to the real file in sites-available (Linux topic 02).

## 03.4 · How to read a config file

```apache
# a comment: Apache ignores it
Listen 80
Timeout 300

<Directory /var/www/>
    Require all granted
</Directory>
```

| Shape | Means |
|---|---|
| `# …` | comment |
| `Name value` | a **directive**: one setting per line |
| `<Block …> … </Block>` | settings that apply only inside it |

Directive names ignore capitals (`listen` = `Listen`). **Paths do not** (`/var/WWW` ≠ `/var/www`).

Read only the real settings of the main file:

```bash
grep -v -E "^\s*#|^\s*$" /etc/apache2/apache2.conf
```

## 03.5 · Settings live at three levels

```
┌ Whole server ─ apache2.conf, ports.conf, conf-enabled/   e.g. Listen 80, Timeout 300
│  ┌ One website ─ inside <VirtualHost>                     e.g. ServerName, DocumentRoot, logs
│  │  ┌ One folder ─ inside <Directory>                     e.g. Require, Options
```

The **smaller** level wins: a folder rule beats a site rule, a site rule beats a server rule. "I changed it but nothing happened" usually means a more specific block somewhere else says the opposite.

## 03.6 · envvars: Apache's identity

```bash
grep -E "APACHE_RUN_USER|APACHE_RUN_GROUP|APACHE_LOG_DIR|APACHE_PID_FILE" /etc/apache2/envvars
```

| Variable | Value | Used as |
|---|---|---|
| `APACHE_RUN_USER` | `www-data` | the workers' user |
| `APACHE_RUN_GROUP` | `www-data` | the workers' group |
| `APACHE_LOG_DIR` | `/var/log/apache2` | `${APACHE_LOG_DIR}` in site files |
| `APACHE_PID_FILE` | `/var/run/apache2/apache2.pid` | the parent's PID |

```bash
cat /var/run/apache2/apache2.pid
```

## 03.7 · A team: one parent, many workers

```
visitors ──► door :80 ──► workers (www-data) answer the visitors
                 ▲
           parent (root): opens port 80, starts the workers, replaces any that die
```

```bash
ps -C apache2 -o user,pid,ppid,cmd
pstree -p $(cat /var/run/apache2/apache2.pid)
```

| | Parent | Worker |
|---|---|---|
| runs as | `root`: may do anything | `www-data`: may only read web files |
| job | open port 80 (needs root), manage workers | answer visitors |
| how many | exactly one | several, more when busy |
| if attacked | the whole server is at risk | only the web files are at risk |

- `ps -C apache2` lists only processes **named** apache2.
- `ps -ef | grep apache2` would also show `htcacheclean` (a cache cleaner that ships with Apache; ignore it) and your own grep line.

**Consequence:** every web file and folder must be readable by **www-data** (topic 04).

## 03.8 · Which ports: Listen

```bash
cat /etc/apache2/ports.conf
sudo ss -lntp | grep apache2
```

| File | Says |
|---|---|
| `ports.conf` → `Listen 80` | **open** this door on the machine |
| a site's `<VirtualHost *:80>` | **who answers** at that door |

A new port needs **both** (topic 05). Try one now:

```bash
sudo cp /etc/apache2/ports.conf /etc/apache2/ports.conf.bak
echo "Listen 8090" | sudo tee -a /etc/apache2/ports.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
sudo ss -lntp | grep apache2
curl -I http://localhost:8090/
```

Port 8090 is now open and answers with the **default** site (it is the only site; Apache falls back to it). Undo:

```bash
sudo cp /etc/apache2/ports.conf.bak /etc/apache2/ports.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
```

## 03.9 · Timeouts and KeepAlive

```bash
grep -n -E "^(Timeout|KeepAlive|MaxKeepAliveRequests|KeepAliveTimeout)" /etc/apache2/apache2.conf
```

| Directive | Ubuntu default | Means |
|---|---|---|
| `Timeout` | 300 | give up on a stuck request after 300 s |
| `KeepAlive` | On | reuse one connection for many requests (page + CSS + images) |
| `MaxKeepAliveRequests` | 100 | max requests on one connection |
| `KeepAliveTimeout` | 5 | idle 5 s → close it and free the worker |

```
one connection:  [connect][page][style.css][logo.png][ idle 5 s ][closed]
```

Topic 09 measures KeepAlive's effect.

## 03.10 · Red Hat names (same software)

| | Ubuntu | Red Hat / Rocky |
|---|---|---|
| package / service | `apache2` | `httpd` |
| main file | `/etc/apache2/apache2.conf` | `/etc/httpd/conf/httpd.conf` |
| extra files | `sites-enabled/`, `a2ensite` | `/etc/httpd/conf.d/*.conf` (no a2ensite) |
| logs | `/var/log/apache2/` | `/var/log/httpd/` |
| worker user | `www-data` | `apache` |
| test | `apache2ctl configtest` | `apachectl configtest` / `httpd -t` |

---

## Exercises

1. Which file says Apache listens on port 80? Show the line with its line number.
2. Which module files are switched on? Count them.
3. Prove the workers run as www-data and the parent as root, in one command.
4. `sites-enabled/000-default.conf`: is it a file or a link? Where does it point?
5. Show only the real (non-comment, non-empty) settings of `ports.conf`.

## Answers

1. `grep -n Listen /etc/apache2/ports.conf`.
2. `ls /etc/apache2/mods-enabled/*.load | wc -l`.
3. `ps -C apache2 -o user,pid,ppid,cmd`: one `root` line (PPID 1), the rest `www-data` with the root PID as PPID.
4. A link: `ls -l` shows `->`; `readlink -f` → `/etc/apache2/sites-available/000-default.conf`.
5. `grep -v -E "^\s*#|^\s*$" /etc/apache2/ports.conf`.
