# 14 · Status page and worker tuning

**Time:** 50 min

**You will learn:** read the full `server-status` page and every scoreboard letter, how the event MPM numbers fit together, how much memory a worker uses, how to fill every worker on purpose and read the `MaxRequestWorkers` error, and how to size the setting with numbers instead of guessing.

Uses the slow page `/cgi-bin/slow.sh` from topic 13.

---

## 14.1 · The full status page

```bash
curl -s "http://localhost/server-status" | sed 's/<[^>]*>//g' | grep -v "^\s*$" | head -n 25
```

- `sed 's/<[^>]*>//g'` removes the HTML tags so the page reads well in a terminal.
- The `?auto` version (topic 06) is for scripts and monitoring tools; this full version is for people.

| Line | Means |
|---|---|
| `Server uptime` | time since the last **restart** (a reload does not reset it) |
| `Total accesses` / `Total Traffic` | requests and bytes since then |
| `requests/sec - B/second - B/request - ms/request` | averages since start |
| `N requests currently being processed, M workers gracefully restarting, K idle workers` | right now |
| the table at the bottom | one row per busy slot: client, site, request, seconds so far |

## 14.2 · The scoreboard, letter by letter

```bash
curl -s "http://localhost/server-status?auto" | grep -E "^(BusyWorkers|IdleWorkers|Processes|Scoreboard)"
```

| Letter | The worker slot is… |
|---|---|
| `_` | waiting for a request (idle, ready) |
| `S` | starting up |
| `R` | reading the request |
| `W` | sending the reply (working) |
| `K` | keep-alive: waiting for the next request on the same connection |
| `D` | DNS lookup |
| `C` | closing the connection |
| `L` | logging |
| `G` | gracefully finishing (after a reload) |
| `I` | idle cleanup |
| `.` | empty slot: no process there yet |

- Many `W` = busy sending: slow back end or big files.
- Many `R` = clients sending slowly (or a slow-request attack).
- Many `G` right after a reload = old workers finishing their downloads: normal.
- All `W`, no `_` = **full**: new visitors wait (14.5).

## 14.3 · How the event MPM numbers fit together

```bash
grep -v -E "^\s*#|^\s*$" /etc/apache2/mods-available/mpm_event.conf
```

```
 ServerLimit (default 16) child processes, at most
   × ThreadsPerChild 25 threads each
 = up to 400 threads possible
 MaxRequestWorkers 150  ← the real ceiling: requests served at the same moment
```

| Rule | Why |
|---|---|
| `MaxRequestWorkers` ≤ `ServerLimit` × `ThreadsPerChild` | otherwise Apache lowers it and logs a warning |
| `MaxRequestWorkers` is a multiple of `ThreadsPerChild` | children come in blocks of 25 |
| `ThreadsPerChild` ≤ `ThreadLimit` (64) | hard limit per child |
| `MinSpareThreads` / `MaxSpareThreads` | how many idle threads to keep ready |

- Default: 150 / 25 = up to **6 children** of 25 threads.

## 14.4 · How much memory does a worker use?

```bash
ps -C apache2 -o pid,user,rss,cmd
ps -C apache2 -o rss= | awk '{s+=$1} END {printf "%d processes, %.0f MB total\n", NR, s/1024}'
free -m | grep Mem
```

- `RSS` = memory in KB really used by each process.
- With the event MPM, memory is counted per **child process** (25 threads share it).
- Sizing rule of thumb:

```
memory for Apache  =  available memory − what other services need (Tomcat, database…)
children possible  =  memory for Apache ÷ RSS of one child
MaxRequestWorkers  =  children possible × ThreadsPerChild     (and not above the CPU's real capacity)
```

- Example: 2000 MB for Apache, 20 MB per child → 100 children → far more than 150 workers. Memory is rarely the limit for static sites; it **is** for mod_php (prefork, 50–100 MB per process).

## 14.5 · Fill every worker on purpose

Shrink the ceiling to 10 workers (lab only):

```bash
sudo cp /etc/apache2/mods-available/mpm_event.conf /etc/apache2/mods-available/mpm_event.conf.bak
sudo vi /etc/apache2/mods-available/mpm_event.conf
```

Make the block read:

```apache
<IfModule mpm_event_module>
	StartServers             1
	ServerLimit              2
	MinSpareThreads          5
	MaxSpareThreads          10
	ThreadLimit              64
	ThreadsPerChild          5
	MaxRequestWorkers        10
	MaxConnectionsPerChild   0
</IfModule>
```

```bash
sudo apache2ctl configtest && sudo systemctl restart apache2
curl -s "http://localhost/server-status?auto" | grep -E "^(BusyWorkers|IdleWorkers|Scoreboard)"
```

- MPM settings need a **restart**.
- 2 children × 5 threads = 10 slots: the scoreboard is now 10 characters long.

Send 30 slow requests at once (each takes 5 s), and look while they run:

```bash
for i in $(seq 1 30); do curl -s -o /dev/null "http://localhost/cgi-bin/slow.sh?5" & done; sleep 2; curl -s "http://localhost/server-status?auto" | grep -E "^(BusyWorkers|IdleWorkers|Scoreboard)"; wait
sudo grep "MaxRequestWorkers" /var/log/apache2/error.log | tail -n 1
```

Sample line:

```text
[Fri Nov 13 00:39:29.478536 2026] [mpm_event:error] [pid 8418:tid 281473098465312] AH00484: server reached MaxRequestWorkers setting, consider raising the MaxRequestWorkers setting
```

- `&` sends each curl to the background, so all 30 start together; `wait` waits for all of them.
- The scoreboard shows almost only `W`: every slot is busy.
- `AH00484` is written **once** when the ceiling is first hit (again only after a restart): look for the **first** time, it tells you when trouble started.
- The 30 requests take about 15 s in total instead of 5 s: they queue in groups of 10.
- A request for a tiny static page sent during the flood also waits in that queue (exercise 4).

Measure what users feel, with `ab`:

```bash
ab -n 40 -c 20 "http://localhost/cgi-bin/slow.sh?1" | grep -E "Requests per second|Time per request|Failed|  50%|  95%|longest"
```

- With 10 workers and 20 at a time, half the users wait about twice as long as the page needs.

## 14.6 · Fix: raise the ceiling, or remove the slowness

```bash
sudo cp /etc/apache2/mods-available/mpm_event.conf.bak /etc/apache2/mods-available/mpm_event.conf
sudo apache2ctl configtest && sudo systemctl restart apache2
ab -n 40 -c 20 "http://localhost/cgi-bin/slow.sh?1" | grep -E "Requests per second|  50%|  95%|longest"
```

- With 150 workers every request gets a worker at once: the times drop to about 1 s.
- In real life, before raising `MaxRequestWorkers`, ask **why** requests are slow (topic 13: `%D` per URL). Raising the ceiling for a slow database only queues more work on the database.

| You see | Do |
|---|---|
| `AH00484`, slow URLs in `%D`, back end slow | fix the back end; raising the ceiling makes it worse |
| `AH00484`, fast URLs, lots of traffic, memory free | raise `MaxRequestWorkers` (and `ServerLimit` if needed) |
| memory almost gone (`free -m`) | do **not** raise it; the server would start swapping |

---

## Exercises

1. Which letters would you expect on the scoreboard right after a reload during a big download?
2. Set `MaxRequestWorkers 500` (keep ThreadsPerChild 25 and the default ServerLimit 16). What does Apache do? Try it with configtest, then restore the `.bak`.
3. How many child processes and threads does the default event configuration allow at most?
4. While 30 slow requests run with the 10-worker setting, does `/hello.html` still answer quickly? Try it and explain.
5. Your server has `AH00484` at 10:31 every day and `%D` shows `/cgi-bin/statement.sh` at 4–6 s from 10:30. What do you tell the application team?

## Answers

1. `G` for the old workers finishing, `_` and `W` for the new ones.
2. It still starts, but lowers the value: `AH00515: WARNING: MaxRequestWorkers of 500 would require 20 servers and would exceed ServerLimit of 16, decreasing to 400. To increase, please see the ServerLimit directive.` (in configtest and in journalctl).
3. ServerLimit 16 × ThreadsPerChild 25 = 400 threads possible, but MaxRequestWorkers 150 = 6 children × 25 in use at most.
4. No. In the test, a `curl -w "%{time_total}"` for `/hello.html` sent 2 s after the flood took **13 s**: it waited in the same queue behind the slow requests. When workers are full, **every** URL is slow, even static files. That is why one slow page can make a whole site look down.
5. The statement page becomes slow at 10:30, holds workers, and fills the server at 10:31; the cause is in the application or database behind that page, not in Apache. Send them the `%D` lines.
