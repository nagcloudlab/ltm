# 07 · Performance: capacity, keepalive, gzip, caching, status

**Time:** 40 min

**You will learn:** how many visitors Nginx can hold, keepalive settings, gzip, browser caching headers, file-serving tuning, the `stub_status` page, and load testing Nginx next to Apache.

---

## 07.1 · Capacity: workers × connections

```bash
grep -n -E "worker_processes|worker_connections|multi_accept" /etc/nginx/nginx.conf
nproc
```

```text
2 cores → worker_processes auto → 2 workers
each worker: worker_connections 768
capacity ≈ 2 × 768 = 1,536 open connections at once
```

| Setting | Context | Ubuntu default | Means |
|---|---|---|---|
| `worker_processes` | main | `auto` | one per core |
| `worker_connections` | events | 768 | connections per worker |
| `worker_rlimit_nofile` | main | (unset) | max open files per worker; must be ≥ connections |

- When every connection slot is in use, new visitors wait or fail; Nginx can log `worker_connections are not enough`.
- Every connection also needs an open file. If the open-file limit is lower, the site's error log shows `accept4() failed (24: Too many open files)` (topic 11 lets you see it).
- Compare Apache: `MaxRequestWorkers 150`.

```bash
sudo grep -rh -E "worker_connections are not enough|Too many open files" /var/log/nginx/
P=$(pgrep -f "nginx: worker" | head -n 1)
sudo grep "open files" /proc/$P/limits
```

- `Max open files 1024` is the usual soft limit for a worker. 768 connections fit under it.

## 07.2 · stub_status: live numbers

```bash
sudo nginx -V 2>&1 | grep -o with-http_stub_status_module
sudo vi /etc/nginx/sites-available/shop
```

```nginx
    location = /nginx_status {
        stub_status;
        allow 127.0.0.1;
        deny all;
        access_log off;
    }
```

```bash
sudo nginx -t && sudo systemctl reload nginx
curl http://localhost:8081/nginx_status
```

| Line | Means |
|---|---|
| `Active connections` | open right now |
| `accepts handled requests` | totals since start: connections accepted, handled, requests |
| `Reading` | reading a request header |
| `Writing` | sending a response |
| `Waiting` | idle keep-alive connections |

`accepts` ≠ `handled` means connections were dropped: limits reached.

## 07.3 · Load test Nginx and Apache side by side

```bash
ab -n 5000 -c 100 http://localhost:8081/ | grep -E "Requests per second|Failed|Time per request"
ab -n 5000 -c 100 http://localhost/ | grep -E "Requests per second|Failed|Time per request"
```

Watch Nginx during the test (second terminal):

```bash
watch -n 1 curl -s http://localhost:8081/nginx_status
```

For small static files both are fast; the difference shows with many slow or idle connections. Try many idle keep-alive clients:

```bash
ab -k -n 20000 -c 500 http://localhost:8081/ | grep -E "Requests per second|Failed"
ab -k -n 20000 -c 500 http://localhost/ | grep -E "Requests per second|Failed"
```

- Apache needs one worker per open connection (150 by default), so at concurrency 500 requests queue.
- Nginx holds all 500 in its few workers.
- Results vary with the VM: write down your numbers, do not expect a fixed winner for tiny pages.

## 07.4 · Keepalive

```bash
grep -n keepalive /etc/nginx/nginx.conf
```

| Setting | Default | Means |
|---|---|---|
| `keepalive_timeout` | 75s (if not set) | close an idle connection after this |
| `keepalive_requests` | 1000 | requests per connection before closing |

Set it explicitly in `http`:

```nginx
    keepalive_timeout 15s;
```

Long timeouts keep idle connections (the `Waiting` number) high; Nginx handles that cheaply, but very long values waste file handles.

## 07.5 · gzip: compression

```bash
grep -n gzip /etc/nginx/nginx.conf
for i in $(seq 1 300); do echo "<p>Line $i of the shop terms and conditions.</p>"; done | sudo tee /var/www/shop/terms.html > /dev/null
curl -s -o /dev/null -w "plain: %{size_download}\n" http://localhost:8081/terms.html
curl -s -o /dev/null -w "gzip:  %{size_download}\n" -H "Accept-Encoding: gzip" http://localhost:8081/terms.html
curl -s -o /dev/null -w "css gzip: %{size_download}\n" -H "Accept-Encoding: gzip" http://localhost:8081/style.css
```

Ubuntu has `gzip on;` but the `gzip_types` line is commented out: only **text/html** is compressed. Turn on the rest in `http`:

```bash
sudo tee /etc/nginx/conf.d/gzip.conf <<'EOF'
gzip_vary on;
gzip_comp_level 5;
gzip_min_length 256;
gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;
EOF
sudo nginx -t && sudo systemctl reload nginx
curl -sI -H "Accept-Encoding: gzip" http://localhost:8081/terms.html | grep -i -E "content-encoding|vary"
```

| Setting | Means |
|---|---|
| `gzip_types` | which types (text/html is always included) |
| `gzip_min_length 256` | skip tiny files (not worth it) |
| `gzip_comp_level 5` | 1 fast … 9 small; 4–6 is the usual balance |
| `gzip_vary on` | send `Vary: Accept-Encoding` for caches |

If `nginx -t` warns about a duplicate, it means `nginx.conf` already has that line uncommented: remove one.

## 07.6 · Browser caching

```nginx
    location ~* \.(css|js|png|jpg|svg|woff2)$ {
        expires 7d;
        add_header Cache-Control "public";
        include snippets/security-headers.conf;
    }
```

(Replace the topic-04 `~* \.(css|png)$` test location with this one.)

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -sI http://localhost:8081/style.css | grep -i -E "expires|cache-control"
LM=$(curl -sI http://localhost:8081/style.css | grep -i last-modified | cut -d' ' -f2- | tr -d '\r')
curl -sI -H "If-Modified-Since: $LM" http://localhost:8081/style.css | head -n 1
```

`expires 7d` sends `Expires` and `Cache-Control: max-age=604800`. A repeat request with `If-Modified-Since` gets **304 Not Modified**: headers only, no body.

## 07.7 · Serving files efficiently

| Setting | Ubuntu | Means |
|---|---|---|
| `sendfile on;` | on | the kernel copies file → network directly |
| `tcp_nopush on;` | on | send headers and the start of the file together |
| `open_file_cache max=1000 inactive=20s;` | off | remember open files and their sizes |

```bash
sudo tee /etc/nginx/conf.d/filecache.conf <<'EOF'
open_file_cache max=1000 inactive=20s;
open_file_cache_valid 30s;
open_file_cache_errors on;
EOF
sudo nginx -t && sudo systemctl reload nginx
```

> With `open_file_cache`, a changed file may be seen up to 30 s later. Remember this when "I updated the page but Nginx shows the old one".

## 07.8 · Performance checklist

| Check | Command |
|---|---|
| workers = cores | `ps -ef \| grep "[n]ginx: worker" \| wc -l` |
| connections limit not hit | `grep "worker_connections are not enough" /var/log/nginx/error.log` |
| live state | `curl localhost:8081/nginx_status` |
| gzip for CSS/JS/JSON | `curl -sI -H "Accept-Encoding: gzip" …/style.css` |
| caching headers on static files | `curl -sI …/style.css \| grep -i cache-control` |
| slow requests | `rt=` in the access log (topic 06) |

---

## Exercises

1. What is this VM's theoretical connection capacity? Show the two numbers.
2. During `ab -k -n 20000 -c 500`, what is the highest `Active connections` you see?
3. Prove JSON is now gzipped.
4. Make images cacheable for 30 days but CSS for 1 day.
5. `accepts 5000 handled 4800`. What does that tell you?

## Answers

1. `nproc` × `worker_connections` (768): 2 × 768 = 1536 on a 2-core VM.
2. Up to about 500 (the concurrency).
3. `curl -sI -H "Accept-Encoding: gzip" http://localhost:8081/health.json | grep -i content-encoding` (the file must be ≥ `gzip_min_length`; lower it or use a bigger JSON file to see it).
4. Two locations: `~* \.(png|jpg|svg)$ { expires 30d; }` and `~* \.css$ { expires 1d; }`.
5. 200 connections were not handled: a limit (worker_connections or open files) was hit; check the error log.
