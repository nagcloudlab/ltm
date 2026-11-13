# 11 · Redirects and rewrites in depth, and redirect loops

**Time:** 40 min

**You will learn:** `return` vs `rewrite`, the four `rewrite` flags tested side by side, keeping the query string, redirects that use variables, a 301 redirect loop and a rewrite cycle (500) on purpose, and how to watch rewrites in the error log with `rewrite_log`.

**Before you start:** topics 04 (locations) and 10. Everything here uses a separate practice site, `lab`, on port **8083**, so the shop stays safe.

---

## 11.1 · A practice site on 8083

```bash
sudo mkdir -p /var/www/lab/docs /var/www/lab/new
echo "<h1>Lab home</h1>" | sudo tee /var/www/lab/index.html
echo "<h1>Docs index</h1>" | sudo tee /var/www/lab/docs/index.html
echo "<h1>New page</h1>" | sudo tee /var/www/lab/new/page.html
sudo tee /etc/nginx/sites-available/lab <<'EOF'
server {
    listen 8083;
    server_name lab.example.com;
    root /var/www/lab;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    access_log /var/log/nginx/lab-access.log;
    error_log  /var/log/nginx/lab-error.log;
}
EOF
sudo ln -s /etc/nginx/sites-available/lab /etc/nginx/sites-enabled/
grep -q "lab.example.com" /etc/hosts || echo "127.0.0.1 lab.example.com" | sudo tee -a /etc/hosts
sudo nginx -t && sudo systemctl reload nginx
curl http://lab.example.com:8083/
```

## 11.2 · return vs rewrite

- `return 301 URL;` — answer **now** with a redirect. Fast, simple, easy to read.
- `rewrite REGEX REPLACEMENT FLAG;` — change the URL with a pattern. Use it when you need a **captured part** (`$1`).

| You want | Use |
|---|---|
| a whole site or one fixed page moved | `return 301 …;` |
| `/old/<anything>` → `/new/<same anything>` | `rewrite ^/old/(.*)$ /new/$1 permanent;` |
| change the path internally, no redirect | `rewrite … last;` |

## 11.3 · The four rewrite flags, side by side

Add four test lines to the `lab` server block (outside `location`):

```bash
sudo sed -i 's#    location / {#    rewrite ^/p/(.*)$ /new/$1 permanent;\n    rewrite ^/r/(.*)$ /new/$1 redirect;\n    rewrite ^/l/(.*)$ /new/$1 last;\n\n    location / {#' /etc/nginx/sites-available/lab
cat /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -sI http://lab.example.com:8083/p/page.html | grep -E "HTTP|Location"
curl -sI http://lab.example.com:8083/r/page.html | grep -E "HTTP|Location"
curl -s  http://lab.example.com:8083/l/page.html
sudo tail -n 3 /var/log/nginx/lab-access.log
```

```nginx
    rewrite ^/p/(.*)$ /new/$1 permanent;
    rewrite ^/r/(.*)$ /new/$1 redirect;
    rewrite ^/l/(.*)$ /new/$1 last;
```

| Flag | Client sees | Access log shows |
|---|---|---|
| `permanent` | `301` + `Location: …/new/page.html` | `HEAD /p/page.html … 301` (`curl -I` sends HEAD) |
| `redirect` | `302` + `Location: …/new/page.html` | `HEAD /r/page.html … 302` |
| `last` | `200` and the new page, **same URL** | `GET /l/page.html … 200` (the original URL) |
| `break` | like `last`, but stays in the current location | |

- With `last`, the browser never knows. The access log shows the URL the visitor **asked for**, not the rewritten one.

## 11.4 · Query strings

```bash
curl -sI "http://lab.example.com:8083/p/page.html?id=7" | grep Location
```

- `rewrite` keeps `?id=7` automatically.
- Add `?` at the end of the replacement to **drop** it: `rewrite ^/p/(.*)$ /new/$1? permanent;`.
- With `return`, add it yourself: `return 301 /new/page.html$is_args$args;` (`$is_args` is `?` only when there are args).

## 11.5 · Redirects with variables

| Variable | Example value |
|---|---|
| `$scheme` | `http` |
| `$host` | `lab.example.com` (from the Host header) |
| `$request_uri` | `/p/page.html?id=7` (path **and** query, as sent) |
| `$uri` | `/p/page.html` (path only, after rewrites) |
| `$args` | `id=7` |

- The standard "move to another name" redirect: `return 301 https://www.example.com$request_uri;`

## 11.6 · Break it: a 301 redirect loop

The lab site redirects **everything** to its own address (a typical mistake when someone "forces" a host name but the name already matches):

```bash
sudo cp /etc/nginx/sites-available/lab /etc/nginx/sites-available/lab.bak
sudo sed -i 's#    location / {#    return 301 http://lab.example.com:8083$request_uri;\n\n    location / {#' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -sI http://lab.example.com:8083/docs/ | grep -E "HTTP|Location"
curl -sS -L --max-redirs 5 -o /dev/null http://lab.example.com:8083/docs/
sudo tail -n 6 /var/log/nginx/lab-access.log
```

- curl: `curl: (47) Maximum (5) redirects followed`. A browser says **"too many redirects"** (`ERR_TOO_MANY_REDIRECTS`).
- `nginx -t` is happy: a loop is valid config.
- Sample access-log lines:

```text
127.0.0.1 - - [13/Nov/2026:10:01:02 +0000] "GET /docs/ HTTP/1.1" 301 162 "-" "curl/8.5.0"
127.0.0.1 - - [13/Nov/2026:10:01:02 +0000] "GET /docs/ HTTP/1.1" 301 162 "-" "curl/8.5.0"
127.0.0.1 - - [13/Nov/2026:10:01:02 +0000] "GET /docs/ HTTP/1.1" 301 162 "-" "curl/8.5.0"
```

- How to read it: the **same client**, the **same URL**, `301` again and again within one second. The `Location` header points back to where the client already is.
- Fix: a redirect must only fire when the request is **not** already right (for example a separate server block for the old name), or be removed.

```bash
sudo cp /etc/nginx/sites-available/lab.bak /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -sI http://lab.example.com:8083/docs/ | head -n 1
```

The correct shape (one block for the old name, one for the real one):

```nginx
server {
    listen 8083;
    server_name old-lab.example.com;
    return 301 http://lab.example.com:8083$request_uri;
}
```

## 11.7 · Break it: a rewrite cycle (500)

```bash
sudo cp /etc/nginx/sites-available/lab /etc/nginx/sites-available/lab.bak
sudo sed -i 's#        try_files $uri $uri/ =404;#        rewrite ^/(.*)$ /x/$1 last;#' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null -w "%{http_code}\n" http://lab.example.com:8083/a
sudo tail -n 1 /var/log/nginx/lab-error.log
```

Sample line:

```text
2026/11/13 00:39:37 [error] 5320#5320: *26 rewrite or internal redirection cycle while processing "/x/x/x/x/x/x/x/x/x/x/x/a", client: 127.0.0.1, server: lab.example.com, request: "GET /a HTTP/1.1", host: "lab.example.com:8083"
```

- `last` sends `/x/a` back through location matching; `location /` matches again and adds another `/x/`.
- Nginx stops after 10 rounds and answers **500**. The growing `/x/x/x/…` path in the message is the clue.
- A 301 loop is in the **access log** (and the browser); a rewrite cycle is in the **error log** (500).

```bash
sudo cp /etc/nginx/sites-available/lab.bak /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
```

## 11.8 · Watch rewrites happen: rewrite_log

```bash
sudo sed -i 's#    error_log  /var/log/nginx/lab-error.log;#    error_log  /var/log/nginx/lab-error.log notice;\n    rewrite_log on;#' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
curl -s -o /dev/null http://lab.example.com:8083/p/page.html
sudo tail -n 2 /var/log/nginx/lab-error.log
```

Sample lines:

```text
2026/11/13 00:40:06 [notice] 5527#5527: *33 "^/p/(.*)$" matches "/p/page.html", client: 127.0.0.1, server: lab.example.com, request: "GET /p/page.html HTTP/1.1", host: "lab.example.com:8083"
2026/11/13 00:40:06 [notice] 5527#5527: *33 rewritten redirect: "/new/page.html", client: 127.0.0.1, server: lab.example.com, request: "GET /p/page.html HTTP/1.1", host: "lab.example.com:8083"
```

- `rewrite_log on;` writes each rule that matched, at level `notice`, so the error log level must be `notice` (or `info`).
- Turn it off afterwards: it is noisy.

```bash
sudo sed -i 's#    error_log  /var/log/nginx/lab-error.log notice;#    error_log  /var/log/nginx/lab-error.log;#; /rewrite_log on;/d' /etc/nginx/sites-available/lab
sudo nginx -t && sudo systemctl reload nginx
```

---

## Exercises

1. Redirect `/blog/<anything>` on the lab site to `http://blog.example.com:8081/<anything>` with one `rewrite` line.
2. Do the same with `return` for the single page `/contact` → `/docs/`.
3. Make `/l/<x>` answer from `/new/<x>` and prove in the access log that the visitor's URL was kept.
4. A user says "too many redirects". Which log and which pattern prove a loop?
5. You see `500` and `rewrite or internal redirection cycle`. Which flag is usually involved, and why?

## Answers

1. `rewrite ^/blog/(.*)$ http://blog.example.com:8081/$1 permanent;`.
2. `location = /contact { return 301 /docs/; }`.
3. `rewrite ^/l/(.*)$ /new/$1 last;` (11.3); access log shows `GET /l/page.html … 200`.
4. Access log: same client and URL with `301`/`302` many times in a second; `curl -sI` shows a `Location` equal to the URL asked.
5. `last` (or a `try_files` / `error_page` that points back into the same location): each round matches the same rule again.
