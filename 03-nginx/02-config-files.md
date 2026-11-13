# 02 · Where Nginx keeps things, and how its config is built

**Time:** 35 min

**You will learn:** the four places, every file in `/etc/nginx`, how config is built from nested blocks (contexts), `nginx.conf` line by line, how files are included, `nginx -T`, and the Apache → Nginx dictionary.

---

## 02.1 · Four places

| What | Where |
|---|---|
| settings | `/etc/nginx/` |
| web pages | any folder you choose (`/var/www/shop`) |
| logs | `/var/log/nginx/` |
| service · user | `nginx` · workers run as `www-data` |

## 02.2 · Inside /etc/nginx

```bash
ls -l /etc/nginx
sudo apt install -y tree
tree -L 1 /etc/nginx
```

```text
/etc/nginx/
├── conf.d/              extra settings, *.conf loaded automatically
├── fastcgi.conf …       helpers for PHP (not used here)
├── mime.types           extension → Content-Type
├── modules-enabled/     dynamic modules switched on
├── nginx.conf           the main file
├── proxy_params         settings for reverse proxy (later module)
├── sites-available/     one file per website
├── sites-enabled/       links to sites switched on
└── snippets/            small reusable pieces
```

## 02.3 · The shape of Nginx config: blocks inside blocks

```text
main context          (user, worker_processes, error_log)
├── events { }        (connections per worker)
└── http { }          (everything about the web)
    └── server { }    one website  =  Apache <VirtualHost>
        └── location /path { }   rules for a URL path  ≈  Apache <Directory>
```

| Rule | Example |
|---|---|
| a **directive** ends with `;` | `root /var/www/shop;` |
| a **block** is `name { … }` | `location / { … }` |
| comments start with `#` | `# a comment` |
| inner blocks inherit outer settings | `gzip on;` in `http` applies to every server |
| a directive works only in some contexts | `listen` only inside `server` |

Wrong context = `nginx -t` error: `"listen" directive is not allowed here`.

## 02.4 · nginx.conf, line by line

```bash
grep -v -E "^\s*#|^\s*$" /etc/nginx/nginx.conf
```

| Line | Context | Means |
|---|---|---|
| `user www-data;` | main | workers run as www-data |
| `worker_processes auto;` | main | one worker per CPU core |
| `pid /run/nginx.pid;` | main | the master's PID file |
| `error_log /var/log/nginx/error.log;` | main | the main error log |
| `include /etc/nginx/modules-enabled/*.conf;` | main | load dynamic modules |
| `worker_connections 768;` | events | connections each worker may hold |
| `sendfile on;` | http | let the kernel send files directly (fast) |
| `tcp_nopush on;` | http | send headers and file start together (topic 07) |
| `types_hash_max_size 2048;` | http | size of the internal MIME table: leave it |
| `include /etc/nginx/mime.types;` | http | extension → Content-Type |
| `default_type application/octet-stream;` | http | unknown extension → "download it" |
| `ssl_protocols …;` · `ssl_prefer_server_ciphers on;` | http | HTTPS defaults (topic 10) |
| `access_log /var/log/nginx/access.log;` | http | main access log |
| `gzip on;` | http | compression (topic 07) |
| `include /etc/nginx/conf.d/*.conf;` | http | extra settings |
| `include /etc/nginx/sites-enabled/*;` | http | **websites** |

## 02.5 · What is really loaded: nginx -T

`nginx -T` tests the config **and prints every loaded file**, each starting with a `# configuration file …` line.

```bash
sudo nginx -T | grep "# configuration file"
sudo nginx -T | grep -n -E "listen|server_name|root"
sudo nginx -T > ~/nginx-before.txt
```

| Use | Command |
|---|---|
| which files are loaded | `nginx -T \| grep "# configuration file"` |
| which site listens where | `nginx -T \| grep -n listen` |
| snapshot before a change | `nginx -T > ~/nginx-before.txt`, later `diff` |

## 02.6 · Which setting wins? Inheritance

```nginx
http {
    gzip on;                  # every server gets gzip
    server {
        gzip off;             # … except this one
        location /api/ {
            gzip on;          # … except this path
        }
    }
}
```

Inner blocks override outer ones, like Apache's three levels. **Exception to remember:** `add_header` lines in an inner block **replace all** `add_header` lines from outer blocks (topic 05).

## 02.7 · Apache → Nginx dictionary

| Apache | Nginx |
|---|---|
| `Listen 80` + `<VirtualHost *:80>` | `listen 80;` inside `server { }` |
| `ServerName` / `ServerAlias` | `server_name a b c;` |
| `DocumentRoot` | `root` |
| `DirectoryIndex` | `index` |
| `<Directory>` (folders on disk) | `location` (URL paths) |
| `Options Indexes` | `autoindex on;` |
| `Alias /docs /srv/docs` | `location /docs/ { alias /srv/docs/; }` |
| `Redirect permanent` | `return 301` |
| `ErrorDocument` | `error_page` |
| `Require local` | `allow 127.0.0.1; deny all;` |
| `ServerTokens Prod` | `server_tokens off;` |
| `apache2ctl configtest` | `nginx -t` |
| `apache2ctl -S` | `nginx -T \| grep -E "listen\|server_name"` |
| `a2ensite x` / `a2dissite x` | `ln -s …/sites-available/x …/sites-enabled/` / `rm …/sites-enabled/x` |
| `.htaccess` | **no equivalent**: all config lives in `/etc/nginx` |

## 02.8 · Red Hat names

| | Ubuntu | Red Hat / Rocky |
|---|---|---|
| sites | `sites-available` + `sites-enabled` | **only** `/etc/nginx/conf.d/*.conf` |
| worker user | `www-data` | `nginx` |
| default page | `/var/www/html` | `/usr/share/nginx/html` |

On Red Hat, a site is just a `.conf` file in `conf.d/`; to disable it, rename it to `.conf.off`.

---

## Exercises

1. List every config file Nginx loaded, in order.
2. Which line makes Nginx read your shop site? Show it with its line number.
3. Put `listen 8090;` directly inside `http { }` (not in a server), run `nginx -t`, read the error, undo.
4. Translate to Nginx: `ServerName blog.example.com`, `ServerAlias www.blog.example.com`, `DocumentRoot /var/www/blog`.
5. Where would you put a setting that every website on this server should get?

## Answers

1. `sudo nginx -T | grep "# configuration file"`.
2. `grep -n "sites-enabled" /etc/nginx/nginx.conf`.
3. `[emerg] … "listen" directive is not allowed here in /etc/nginx/nginx.conf:13` (the line number is where you typed it), then `test failed`.
4. `server_name blog.example.com www.blog.example.com;` and `root /var/www/blog;`.
5. In the `http { }` block, or a file in `/etc/nginx/conf.d/` (included inside `http`).
