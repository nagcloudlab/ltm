# 04 · Locations and files: how a URL becomes a file

**Time:** 50 min

**You will learn:** `location` types and how Nginx chooses one, `root` vs `alias`, `try_files` step by step, `index`, folder listings (`autoindex`), Content-Type, redirects with `return` and `rewrite`, and custom error pages.

---

## 04.1 · Some files to work with

```bash
sudo mkdir -p /var/www/shop/images /var/www/shop/docs /var/www/shop/old
echo "body { color: #1b2130; }" | sudo tee /var/www/shop/style.css
echo "PNG-ish" | sudo tee /var/www/shop/images/logo.png
echo "<h1>Docs</h1>" | sudo tee /var/www/shop/docs/index.html
echo '{"status":"ok"}' | sudo tee /var/www/shop/health.json
ls -R /var/www/shop
```

## 04.2 · location: rules per URL path

| Form | Matches | Example |
|---|---|---|
| `location /path/` | paths that **start** with it (prefix) | `/images/logo.png` |
| `location = /path` | **exactly** this path | `/health` only |
| `location ^~ /path/` | prefix, and **stop** looking at regex | static folders |
| `location ~ \.php$` | regex, capitals matter | ends with `.php` |
| `location ~* \.(png\|jpg)$` | regex, ignore capitals | `.PNG`, `.jpg` |
| `location /` | everything (the shortest prefix) | fallback |

### How Nginx chooses (memorise the order)

```text
1  an exact  = match?                        → use it, stop
2  find the LONGEST matching prefix
3  that prefix has ^~ ?                      → use it, stop
4  check regex locations in file order; first match wins
5  no regex matched                          → use the longest prefix from step 2
```

### See it work

Add to the shop server block (keep the existing `location /`):

```nginx
    location = /health {
        default_type application/json;
        return 200 '{"site":"shop","ok":true}';
    }
    location /images/ {
        add_header X-Matched "prefix /images/";
    }
    location ~* \.(css|png)$ {
        add_header X-Matched "regex css|png";
    }
```

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -i http://localhost:8081/health
curl -sI http://localhost:8081/images/logo.png | grep X-Matched
curl -sI http://localhost:8081/style.css | grep X-Matched
```

`/images/logo.png` matches the prefix `/images/` **and** the regex: the regex wins (step 4). Change `location /images/` to `location ^~ /images/`, reload, curl again: now the prefix wins (step 3).

`return 200 '…'` answers directly from config: a health check with no file at all.

## 04.3 · root vs alias

A visitor asks for `/images/logo.png`.

| | `root` | `alias` |
|---|---|---|
| config | `location /images/ { root /data; }` | `location /images/ { alias /data/pics/; }` |
| Nginx looks for | `/data` **+** `/images/logo.png` | `/data/pics/` + `logo.png` |
| rule | root + the **whole** URL path | the location part is **replaced** |

Try alias:

```bash
sudo mkdir -p /srv/manuals
echo "<h1>User manual</h1>" | sudo tee /srv/manuals/index.html
```

```nginx
    location /manuals/ {
        alias /srv/manuals/;
    }
```

```bash
sudo nginx -t && sudo systemctl reload nginx
curl http://localhost:8081/manuals/
```

**Break it:** change `alias` to `root`, reload, curl: **404**. The error log shows the path Nginx really tried:

```bash
sudo tail -n 1 /var/log/nginx/shop-error.log
```

Sample line:

```text
2026/11/12 21:11:17 [error] 3467#3467: *8 "/srv/manuals/manuals/index.html" is not found (2: No such file or directory), client: 127.0.0.1, server: shop.example.com, request: "HEAD /manuals/ HTTP/1.1", host: "localhost:8081"
```

- `/srv/manuals/manuals/…`: root added the **whole** URL path to the folder.
- Put `alias` back and reload.

> With alias, keep the trailing slash on **both** sides: `location /manuals/` + `alias /srv/manuals/;`. Apache's `Alias` works like Nginx `alias`. Note: Nginx has no `/` lock like Apache's `<Directory />`; any folder www-data can read can be served.

## 04.4 · try_files, one step at a time

```nginx
    location / {
        try_files $uri $uri/ =404;
    }
```

A visitor asks for `/docs`:

| Step | Tries | Result |
|---|---|---|
| `$uri` | the file `/var/www/shop/docs` | not a file |
| `$uri/` | the folder `/var/www/shop/docs/` + `index` | found `docs/index.html` → send it |
| `=404` | (only if both failed) | 404 Not Found |

```bash
curl -I http://localhost:8081/docs
curl -I http://localhost:8081/docs/
curl -I http://localhost:8081/nothing
```

`/docs` gets a **301** to `/docs/` first (Nginx adds the slash for folders).

A common variant for single-page apps: `try_files $uri $uri/ /index.html;` (unknown paths get the app page instead of 404).

## 04.5 · index and autoindex

```bash
curl -I http://localhost:8081/images/
sudo tail -n 1 /var/log/nginx/shop-error.log
```

**403**: `directory index of "/var/www/shop/images/" is forbidden`. No index file, and listings are **off by default** (safer than Apache on Ubuntu).

Turn a listing on for one path only. **Edit the existing `/images/` location** from 04.2 (two `location /images/` blocks in one server = `duplicate location` error):

```nginx
    location ^~ /images/ {
        add_header X-Matched "prefix /images/";
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }
```

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -s http://localhost:8081/images/
```

`exact_size off` shows K/M; `localtime on` shows local time. Switch it back off when done: listings leak file names.

## 04.6 · Content-Type

```bash
curl -sI http://localhost:8081/style.css | grep -i content-type
curl -sI http://localhost:8081/health.json | grep -i content-type
grep -E "text/css|application/json" /etc/nginx/mime.types
```

Unknown extensions get `default_type application/octet-stream`: the browser **downloads** instead of showing. Fix by adding the type to `mime.types` or setting `default_type` in a location.

## 04.7 · Redirects: return

```nginx
    location = /old.html {
        return 301 /index.html;
    }
    location /sale/ {
        return 302 /docs/;
    }
```

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -I http://localhost:8081/old.html
curl -I http://localhost:8081/sale/anything
curl -L http://localhost:8081/old.html
```

| Code | Means | Use |
|---|---|---|
| 301 | moved for good (browser caches it) | renamed pages |
| 302 | moved for now | maintenance, tests |
| 307 / 308 | like 302 / 301 but a POST stays a POST | forms, APIs |

## 04.8 · rewrite: patterns

```nginx
    rewrite ^/old/(.*)$ /docs/$1 permanent;
```

(Inside the `server` block, outside any location.)

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -I http://localhost:8081/old/index.html
```

| Flag | Means |
|---|---|
| `permanent` | 301 redirect |
| `redirect` | 302 redirect |
| `last` | change the URL internally, find a new location (no redirect) |
| `break` | change the URL internally, stay in this location |

Prefer `return` when you can; use `rewrite` when you need the captured part (`$1`).

## 04.9 · Your own error pages

```bash
echo "<h1>Sorry, no such page</h1><p><a href='/'>Shop home</a></p>" | sudo tee /var/www/shop/404.html
```

```nginx
    error_page 404 /404.html;
    location = /404.html {
        internal;
    }
    error_page 500 502 503 504 /50x.html;
```

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -i http://localhost:8081/nothing
curl -I http://localhost:8081/404.html
```

The status stays **404**. `internal` means the page is used only for errors: asking for `/404.html` directly gives 404 too.

---

## Exercises

1. Add `location = /version` that returns `200` with the text `shop v1`. Test it.
2. Serve `/srv/manuals/` at `/help/` using alias. Then explain what `root` would have looked for.
3. Which location answers `/images/a.PNG` with the config from 04.2? Change one line so the prefix wins.
4. Redirect `/shop-old/anything` permanently to `/anything`.
5. Make `/docs/` show a file listing while `/images/` does not.

## Answers

1. `location = /version { default_type text/plain; return 200 'shop v1'; }`, then `curl http://localhost:8081/version`.
2. `location /help/ { alias /srv/manuals/; }`. `root /srv/manuals;` would look for `/srv/manuals/help/…`.
3. The regex `~* \.(css|png)$` (case-insensitive). Use `location ^~ /images/`.
4. `rewrite ^/shop-old/(.*)$ /$1 permanent;`.
5. `location /docs/ { autoindex on; }` and remove the docs `index.html` (or the listing never shows); `/images/` without `autoindex`.
