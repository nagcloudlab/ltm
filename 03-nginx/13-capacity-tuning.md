# 13 · Capacity tuning: workers, connections, open files, file cache

**Time:** 45 min

**You will learn:** how to calculate Nginx capacity, read `stub_status` under load, see what happens when the open-file limit is too low (`Too many open files`), raise the limits safely with `worker_rlimit_nofile`, and when to suspect `open_file_cache`.

**Before you start:** topic 07 (`stub_status`, `ab`). Work on a lab VM only: some steps break Nginx on purpose. Keep a copy of `nginx.conf` first.

```bash
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig
```

---

## 13.1 · The numbers that decide capacity

```bash
nproc
grep -n -E "worker_processes|worker_connections|worker_rlimit_nofile" /etc/nginx/nginx.conf
P=$(pgrep -f "nginx: worker" | head -n 1)
sudo grep "open files" /proc/$P/limits
ps -ef | grep -c "[n]ginx: worker"
```

```text
capacity  ≈  workers  ×  worker_connections
             2 cores  ×  768                  = 1,536 connections (2-core VM)
```

| Limit | Default here | Rule |
|---|---|---|
| `worker_processes` | `auto` = number of cores | leave `auto` |
| `worker_connections` | 768 | connections **one** worker may hold |
| open files per worker | 1024 (soft limit) | must be **more** than `worker_connections`: each connection is a file, plus log files and page files |

- A visitor that is downloading uses **one** connection. With keep-alive, an idle browser also keeps one.

## 13.2 · Watch connections under load

Terminal 1:

```bash
watch -n 1 curl -s http://localhost:8081/nginx_status
```

Terminal 2:

```bash
ab -k -n 50000 -c 300 http://localhost:8081/ | grep -E "Requests per second|Failed"
```

| stub_status line | Read it as |
|---|---|
| `Active connections: 301` | about the `ab` concurrency + you |
| `Reading` | reading request headers (should be small) |
| `Writing` | sending answers right now |
| `Waiting` | idle keep-alive connections |
| `accepts` = `handled` | no connection was dropped by a limit |

## 13.3 · Break it: open-file limit too low

Set one worker with only **30** open files:

```bash
sudo sed -i 's/^worker_processes auto;/worker_processes 1;\nworker_rlimit_nofile 30;/' /etc/nginx/nginx.conf
grep -n -E "worker_processes|worker_rlimit_nofile" /etc/nginx/nginx.conf
sudo nginx -t && sudo systemctl restart nginx
ab -n 2000 -c 50 http://localhost:8081/ | grep -E "Complete requests|Failed requests"
sudo grep -h "Too many open files" /var/log/nginx/shop-error.log | tail -n 2
```

Sample line:

```text
2026/11/13 00:40:19 [crit] 5623#5623: accept4() failed (24: Too many open files)
```

- `accept4()` = taking a new connection. `24` = errno EMFILE: this process hit its open-file limit.
- Level `crit`: Nginx could not take a connection. Waiting connections stay in the kernel queue, so `ab` may still finish with 0 failures, only slower; with more load visitors get timeouts or resets.
- The **error log** shows the problem long before users complain: search it after every load test.
- It is written to the error log of the server block that owns the port (here `shop-error.log`), so search all logs: `sudo grep -rh "Too many open files" /var/log/nginx/`.

Put the original back:

```bash
sudo cp /etc/nginx/nginx.conf.orig /etc/nginx/nginx.conf
sudo nginx -t && sudo systemctl restart nginx
ps -ef | grep -c "[n]ginx: worker"
```

## 13.4 · Raise capacity the right way

For a busy server: more connections per worker **and** a higher open-file limit to match.

```bash
sudo sed -i 's/^worker_processes auto;/worker_processes auto;\nworker_rlimit_nofile 8192;/; s/worker_connections 768;/worker_connections 4096;/' /etc/nginx/nginx.conf
grep -n -E "worker_processes|worker_rlimit_nofile|worker_connections" /etc/nginx/nginx.conf
sudo nginx -t && sudo systemctl restart nginx
P=$(pgrep -f "nginx: worker" | head -n 1)
sudo grep "open files" /proc/$P/limits
```

```nginx
worker_processes auto;
worker_rlimit_nofile 8192;

events {
    worker_connections 4096;
}
```

- `worker_rlimit_nofile 8192` → each worker may open 8192 files (`/proc/<pid>/limits` proves it).
- Rule of thumb: `worker_rlimit_nofile` ≈ 2 × `worker_connections`.
- `restart`, not `reload`, for limits: the new limit is applied when workers start; a restart makes sure every worker has it.

Put the original back (the lab VM does not need this):

```bash
sudo cp /etc/nginx/nginx.conf.orig /etc/nginx/nginx.conf
sudo nginx -t && sudo systemctl restart nginx
```

## 13.5 · open_file_cache: what it keeps, and when to suspect it

```bash
cat /etc/nginx/conf.d/filecache.conf
```

| Line | Means |
|---|---|
| `open_file_cache max=1000 inactive=20s;` | each worker remembers up to 1000 open files, forgets a file not used for 20 s |
| `open_file_cache_valid 30s;` | re-check a remembered file on disk at most every 30 s |
| `open_file_cache_errors on;` | also remember "file not found" |

- Saves an `open()` and `stat()` for every hit on popular files.
- Each worker has its **own** cache, so two requests can see different states for a short time.
- Rule: right after a deploy, if a page looks old or a new file still gives 404 for a few seconds, reload Nginx (new workers start with an empty cache):

```bash
sudo systemctl reload nginx
curl -sI http://localhost:8081/ | head -n 1
```

> "I deployed new files and Nginx shows an old page" → check in this order: `open_file_cache` (reload), browser cache (`expires`, try `curl`), then any CDN in front.

## 13.6 · Tuning checklist

- `worker_processes auto;` — one per core.
- `worker_connections` × workers ≥ expected open connections (keep-alive clients count).
- `worker_rlimit_nofile` ≈ 2 × `worker_connections`; prove it in `/proc/<pid>/limits`.
- `keepalive_timeout 15s;` — fewer idle connections.
- `stub_status`: `accepts` = `handled`, `Waiting` not huge.
- Error logs: no `Too many open files`, no `worker_connections are not enough`.

---

## Exercises

1. A 4-core server has `worker_connections 1024`. What is its connection capacity?
2. The shop error log shows `accept4() failed (24: Too many open files)`. Which two settings do you check, and with which commands?
3. Why is `worker_connections 4096` with a 1024 open-file limit a bad pair?
4. You raised `worker_rlimit_nofile`. How do you prove the running workers got it?
5. Right after a deploy, a new file still answers 404 for some requests. What may be the cause, and what do you run?

## Answers

1. 4 × 1024 = 4096 connections.
2. `worker_rlimit_nofile` (`grep worker_rlimit_nofile /etc/nginx/nginx.conf`) and the worker's real limit (`sudo grep "open files" /proc/<worker pid>/limits`); also `worker_connections`.
3. Each connection needs a file: the worker runs out of files (error 24) long before it reaches 4096 connections.
4. `sudo grep "open files" /proc/$(pgrep -f "nginx: worker" | head -n 1)/limits`.
5. `open_file_cache_errors on` remembered "not found" in some workers; `sudo systemctl reload nginx`.
