# 08 · Services and scheduling

**Time:** 50 min

**Part A · Basics** on your own lab VM. **Part B · In depth** on the PayBank lab server (`~/lab/srv`, built by `00-setup.md`).

**You will learn in Part B:** cron syntax and real admin jobs, why cron jobs fail, `/etc/cron.d`, systemd timers, `at`

---

# Part A · Basics

## 08.1 · Services with systemctl


A **service** is a process that runs all the time, started at boot and watched by **systemd** (PID 1).

```bash
systemctl status cron
```

Press `q` to leave.

| Line | Question it answers |
|---|---|
| `Loaded: … enabled` | starts at boot? |
| `Active: active (running)` | **alive right now?** |
| `Main PID: 640` | its process (same as `pgrep -a cron`) |

### Stop and start it

```bash
sudo systemctl stop cron
systemctl status cron            # press q to leave
sudo systemctl start cron
systemctl is-active cron
systemctl is-enabled cron
```

| Command | Does |
|---|---|
| `status` | is it running? (no sudo needed) |
| `start` / `stop` | now |
| `restart` | stop, then start |
| `reload` | re-read settings, keep running |
| `enable` / `disable` | at boot |

```bash
systemctl list-units --type=service --state=running
```

> **Never stop `ssh`** on a server you reach over ssh: you will lock yourself out.
>
> On Ubuntu 24.04, `systemctl status ssh` may show `disabled` and `TriggeredBy: ssh.socket`. That is normal: systemd starts ssh when someone connects.


---

# Part B · In depth: the PayBank lab server

```bash
cd ~/lab/srv
```

## 08.2 · Your crontab

```bash
crontab -l
crontab -e
```

(First time it asks for an editor: choose `vim.basic` or `nano`.)

## 08.3 · The five time fields

```
┌───────── minute        (0-59)
│ ┌─────── hour          (0-23)
│ │ ┌───── day of month  (1-31)
│ │ │ ┌─── month         (1-12)
│ │ │ │ ┌─ day of week   (0-7, 0 and 7 = Sunday)
│ │ │ │ │
* * * * *   command
```

| Line | Runs |
|---|---|
| `* * * * *` | every minute |
| `*/5 * * * *` | every 5 minutes |
| `0 * * * *` | every hour, on the hour |
| `30 2 * * *` | every day at 02:30 |
| `0 9 * * 1-5` | 09:00 Monday to Friday |
| `0 3 * * 0` | Sunday 03:00 |
| `0 0 1 * *` | midnight on the 1st of each month |
| `15 10,22 * * *` | 10:15 and 22:15 |

| Symbol | Means |
|---|---|
| `*` | every |
| `*/n` | every n |
| `a-b` | range |
| `a,b` | list |

Check any line at **crontab.guru** before saving it.

## 08.4 · Hands-on: a health log every minute

```bash
crontab -e
```

Add this one line, save and quit:

```
* * * * * echo "$(date '+\%F \%T') load=$(cut -d' ' -f1 /proc/loadavg) disk=$(df --output=pcent / | tail -1)" >> $HOME/health.log 2>&1
```

> In a crontab, `%` has a special meaning, so it must be written `\%`.

```bash
crontab -l
sleep 130; cat ~/health.log
grep CRON /var/log/syslog | tail -n 2         # proof cron ran it
```

## 08.5 · Real admin cron lines

- Read these; do not add them now.
- They write into `/var/log` and `/backup`, so they belong in **root's** crontab (`sudo crontab -e`).

```
# Health check every 5 minutes: log non-200 answers from Apache
*/5 * * * * code=$(curl -s -o /dev/null -w '\%{http_code}' http://localhost/) ; [ "$code" = 200 ] || echo "$(date) Apache returned $code" >> /var/log/healthcheck.log

# Disk alert every hour above 80%
0 * * * * [ $(df --output=pcent / | tail -1 | tr -dc 0-9) -gt 80 ] && echo "$(hostname) disk above 80\%" >> /var/log/disk-alert.log

# Remove app logs older than 30 days, Sunday 03:00
0 3 * * 0 find /var/log/payment -name "*.log.gz" -mtime +30 -delete

# Back up Apache config every night 01:00
0 1 * * * tar -czf /backup/apache2-$(date +\%F).tar.gz -C /etc apache2
```

## 08.6 · Why did my cron job not run? (the classic list)

| Cause | Fix |
|---|---|
| cron has a tiny `PATH` (`/usr/bin:/bin`) | use full paths: `/usr/bin/curl`, or set `PATH=` at the top of the crontab |
| `%` not escaped | write `\%` |
| no output, no clue | append `>> file 2>&1` to every job |
| script not executable | `chmod 755 script.sh` |
| needs root | use `sudo crontab -e` or a file in `/etc/cron.d/` |
| wrong time zone assumed | cron uses the server's time zone: `timedatectl` |

## 08.7 · System-wide cron

```bash
ls /etc/cron.d /etc/cron.daily
cat /etc/cron.d/e2scrub_all
```

Files in `/etc/cron.d/` have an **extra field**: the user to run as. Simplified, the line reads:

```
30 3 * * 0 root /usr/lib/x86_64-linux-gnu/e2fsprogs/e2scrub_all_cron
```

- `30 3 * * 0` = Sunday 03:30
- `root` = the extra user field

## 08.8 · systemd timers (the modern cron)

```bash
systemctl list-timers --all | head
```

On Ubuntu, **logrotate runs from a systemd timer**, not cron. Know both exist.

## 08.9 · Run once later: `at`

```bash
sudo apt install -y at
echo "df -h / > ~/disk-at-1800.txt" | at 18:00
echo "systemctl status cron > ~/cron-in-10.txt" | at now + 10 minutes
atq
atrm 1
```

| | cron | at |
|---|---|---|
| repeats | yes | no, once |
| use for | daily cleanup, checks | "restart after the change window tonight" |

## 08.10 · Clean up

```bash
crontab -e      # delete your test line, save
crontab -l
```

---

## Exercises

1. `Active: active (running)`. Does that prove the service works for users? Why not?
2. Write cron lines for: (a) every 10 minutes, (b) 23:45 every day, (c) 06:00 on weekdays, (d) the first Monday… (trick: can cron do it alone?).
3. Your cron job `curl … >> log` works by hand but never runs from cron. Give two likely reasons.
4. Schedule, with `at`, a one-time `uptime` into a file 2 minutes from now, then verify it ran.

## Answers

1. No. It only proves the process is alive. Also check its port (`ss`) and that it answers (e.g. `curl`, Module 3).
2. (a) `*/10 * * * *` (b) `45 23 * * *` (c) `0 6 * * 1-5` (d) not by the five fields alone: `0 9 1-7 * 1` looks right but cron runs it when the day is 1–7 **or** it is Monday. Run on days 1–7 and check the weekday inside the command: `0 9 1-7 * * [ "$(date +\%u)" = 1 ] && cmd`.
3. curl not on cron's PATH (use `/usr/bin/curl`); unescaped `%` in `-w '%{http_code}'`.
4. `echo "uptime > ~/up.txt" | at now + 2 minutes`; after 2 min `cat ~/up.txt`.
