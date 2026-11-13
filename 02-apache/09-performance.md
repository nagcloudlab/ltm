# 09 · Performance: workers, KeepAlive, compression, caching, load testing

**Time:** 40 min

**You will learn:** the three MPMs and which one Ubuntu uses, how many visitors Apache can serve at once, how to watch it under load, measure KeepAlive, turn on compression and browser caching, and load-test with `ab`.

---

## 09.1 · MPM: how Apache organises its workers

```bash
sudo apache2ctl -V | grep -i mpm
ls /etc/apache2/mods-enabled/ | grep mpm
```

| MPM | How it works | Use |
|---|---|---|
| `prefork` | one process per visitor, no threads | old modules that are not thread-safe (e.g. mod_php) |
| `worker` | processes with many threads, one thread per visitor | general |
| **`event`** | like worker, but idle keep-alive connections do **not** hold a thread | **Ubuntu default**: best for most sites |

Only one MPM can be enabled at a time.

## 09.2 · How many visitors at once?

```bash
grep -v -E "^\s*#|^\s*$" /etc/apache2/mods-enabled/mpm_event.conf
```

| Setting | Ubuntu default | Means |
|---|---|---|
| `StartServers` | 2 | child processes at start |
| `ThreadsPerChild` | 25 | threads (workers) per child |
| `MinSpareThreads` / `MaxSpareThreads` | 25 / 75 | keep this many idle, ready |
| `MaxRequestWorkers` | 150 | **the ceiling**: max requests served at the same moment |
| `MaxConnectionsPerChild` | 0 | 0 = never recycle a child |

```
start:   child 1 [25 threads]  child 2 [25 threads]   = 50 workers
busy:    more children, up to MaxRequestWorkers 150
full:    new visitors wait in a queue → slow pages → timeouts
```

The error log warns when the ceiling is hit:

```bash
sudo grep -i "MaxRequestWorkers" /var/log/apache2/error.log
```

`server reached MaxRequestWorkers setting, consider raising the MaxRequestWorkers setting` = all workers busy. Raising it needs enough memory: each busy worker uses RAM.

## 09.3 · Load testing with ab

`ab` (ApacheBench) comes with Apache (`apache2-utils`). Test **only your own server**.

```bash
ab -n 100 -c 10 http://localhost/
ab -n 2000 -c 50 http://localhost/
```

| Option | Means |
|---|---|
| `-n 2000` | total requests |
| `-c 50` | how many at the same time (concurrency) |
| `-k` | use keep-alive |

Read these lines of the result:

| Line | Means |
|---|---|
| `Requests per second` | throughput: higher is better |
| `Time per request (mean)` | how long one user waits |
| `Failed requests` | must be 0 |
| `Non-2xx responses` | errors returned (e.g. 404s) |
| `Percentage … 95%` / `99%` | the slow tail: what the unluckiest users get |

Watch the workers while `ab` runs (two terminals):

```bash
watch -n 1 "curl -s 'http://localhost/server-status?auto' | grep -E 'Busy|Idle|ReqPerSec'"
```

```bash
ab -n 20000 -c 100 http://localhost/
```

## 09.4 · KeepAlive: measure the difference

```bash
ab -n 2000 -c 20 http://localhost/ | grep "Requests per second"
ab -k -n 2000 -c 20 http://localhost/ | grep "Requests per second"
```

`-k` reuses connections: usually clearly faster, because no new TCP connection is opened for each request.

Now turn KeepAlive off on the server and repeat the `-k` test:

```bash
sudo cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf.bak
sudo sed -i 's/^KeepAlive On/KeepAlive Off/' /etc/apache2/apache2.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
ab -k -n 2000 -c 20 http://localhost/ | grep -E "Requests per second|Keep-Alive requests"
sudo cp /etc/apache2/apache2.conf.bak /etc/apache2/apache2.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
```

`Keep-Alive requests: 0` and fewer requests per second: every request paid for a new connection.

## 09.5 · Compression: mod_deflate

Text (HTML, CSS, JS, JSON) shrinks to 10–30% when gzipped. Make a bigger page to see it:

```bash
for i in $(seq 1 300); do echo "<p>Line $i of the PayBank terms and conditions.</p>"; done | sudo tee /var/www/html/terms.html > /dev/null
curl -s -o /dev/null -w "plain:  %{size_download} bytes\n" http://localhost/terms.html
curl -s -o /dev/null -w "gzip:   %{size_download} bytes\n" -H "Accept-Encoding: gzip" http://localhost/terms.html
curl -sI -H "Accept-Encoding: gzip" http://localhost/terms.html | grep -i -E "content-encoding|vary"
```

| Header | Means |
|---|---|
| request `Accept-Encoding: gzip` | "I can unzip" (browsers always send it) |
| response `Content-Encoding: gzip` | "this body is compressed" |
| `Vary: Accept-Encoding` | caches must keep both versions |

```bash
grep -v -E "^\s*#|^\s*$" /etc/apache2/mods-enabled/deflate.conf
```

Only text types are compressed; images and zip files are already compressed. `deflate` is enabled on Ubuntu by default; `a2dismod deflate` would turn it off.

## 09.6 · Browser caching: mod_expires

Tell browsers how long to keep files, so repeat visitors download less:

```bash
sudo a2enmod expires
sudo systemctl restart apache2
sudo vi /etc/apache2/sites-available/000-default.conf
```

```apache
    <IfModule mod_expires.c>
        ExpiresActive On
        ExpiresByType text/css   "access plus 1 week"
        ExpiresByType image/png  "access plus 1 month"
        ExpiresByType text/html  "access plus 0 seconds"
    </IfModule>
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -sI http://localhost/shop/style.css | grep -i -E "cache-control|expires"
curl -sI http://localhost/shop/ | grep -i -E "cache-control|expires"
```

CSS gets `Cache-Control: max-age=604800` (7 days); HTML must be checked every time. When the browser asks again it may get **304 Not Modified**:

```bash
LM=$(curl -sI http://localhost/shop/style.css | grep -i last-modified | cut -d' ' -f2- | tr -d '\r')
curl -sI -H "If-Modified-Since: $LM" http://localhost/shop/style.css | head -n 1
```

## 09.7 · Performance checklist

| Check | Command |
|---|---|
| right MPM (event) | `apache2ctl -V \| grep -i mpm` |
| ceiling not hit | `grep MaxRequestWorkers /var/log/apache2/error.log` |
| workers busy now | `curl -s localhost/server-status?auto` |
| memory left | `free -h` (available) |
| slow URLs | `%D` in the access log (topic 08) |
| KeepAlive on | `grep ^KeepAlive /etc/apache2/apache2.conf` |
| compression on | `Content-Encoding: gzip` |
| caching headers | `Cache-Control` on CSS/images |
| only needed modules | `apache2ctl -M` |

---

## Exercises

1. Which MPM is active, and what is MaxRequestWorkers?
2. Run `ab -n 1000 -c 20` against `/terms.html` with and without `Accept-Encoding: gzip` (`-H`). Compare "Total transferred".
3. While `ab -n 20000 -c 100` runs, what is the highest BusyWorkers you see?
4. Make PNG images cacheable for 1 day only and prove the header.
5. `ab` shows `Non-2xx responses: 1000`. What does that suggest?

## Answers

1. `sudo apache2ctl -V | grep -i mpm` → event; `grep MaxRequestWorkers /etc/apache2/mods-enabled/mpm_event.conf` → 150.
2. `ab -n 1000 -c 20 -H "Accept-Encoding: gzip" http://localhost/terms.html`: much smaller "Total transferred".
3. Up to about 100 (the concurrency), as long as it stays below 150.
4. `ExpiresByType image/png "access plus 1 day"`; `curl -sI …/x.png | grep -i cache-control` → `max-age=86400`.
5. Every request got an error status: wrong URL (404), password needed (401), or blocked (403). Check the access log.
