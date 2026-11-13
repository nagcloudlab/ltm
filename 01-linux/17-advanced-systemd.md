# 17 · Advanced: your own systemd service, restart policies, journalctl

**Time:** 45 min

**Practise on** your own lab VM.

**You will learn:** write a unit file for an app, start it at boot, make systemd restart it after a crash, change settings safely with a drop-in file, filter the journal by unit, time and priority, and replace a cron job with a systemd timer.

- Every app server you will meet (Tomcat, Kong, a Java jar) runs as a **systemd service**.
- Here you build a small pretend app called **paysim** ("payment simulator") so you can start, crash and repair a real service.
- paysim answers HTTP on port **8085**, using Python's built-in web server (`python3` is installed on every Ubuntu server).

---

## 17.1 · What systemd needs: a program and a unit file

```
/opt/paysim/paysim.sh                     the program (any command that keeps running)
/etc/systemd/system/paysim.service        the unit file: how to run it
            │
            ▼
systemctl start paysim  →  systemd runs ExecStart as User, watches it, logs its output
```

- A **unit file** is a small text file with sections in `[brackets]`.
- Your own unit files go in `/etc/systemd/system/`.
- Files that came with packages live in `/usr/lib/systemd/system/`. Do not edit those; override them (17.5).

## 17.2 · Create the program

```bash
sudo mkdir -p /opt/paysim
sudo tee /opt/paysim/paysim.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
# paysim.sh: a pretend payment service. Answers HTTP on port 8085.
echo "paysim starting on port ${PORT:-8085} (env=${APP_ENV:-unset})"
cd /opt/paysim
exec python3 -m http.server "${PORT:-8085}" --bind 127.0.0.1
EOF
sudo chmod 755 /opt/paysim/paysim.sh
echo "payment OK" | sudo tee /opt/paysim/health > /dev/null
ls -l /opt/paysim
```

- `sudo tee file > /dev/null <<'EOF' … EOF` writes the lines between the two `EOF` markers into a file that needs root. (`sudo echo … > file` does not work: the `>` is done by **your** shell, without sudo.)
- `exec` replaces the script with python, so systemd watches python directly.
- The file `health` is what `curl http://127.0.0.1:8085/health` will return.

## 17.3 · Write the unit file and start it

```bash
sudo tee /etc/systemd/system/paysim.service > /dev/null <<'EOF'
[Unit]
Description=PayBank payment simulator
After=network.target

[Service]
User=www-data
Environment=APP_ENV=lab
Environment=PORT=8085
ExecStart=/opt/paysim/paysim.sh
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now paysim
systemctl status paysim --no-pager
curl -s http://127.0.0.1:8085/health
```

| Line | Means |
|---|---|
| `After=network.target` | start after networking is up |
| `User=www-data` | run as this user, **not root** |
| `Environment=KEY=value` | variables the program sees (Topic 12) |
| `ExecStart=` | the full path of the command to run |
| `Restart=on-failure` | start it again if it crashes or exits with an error |
| `RestartSec=3` | wait 3 seconds before restarting |
| `WantedBy=multi-user.target` | `enable` makes it start at every normal boot |

- `daemon-reload` = "systemd, read the unit files again". Needed after **every** change to a unit file.
- `enable --now` = enable at boot **and** start now.
- `--no-pager` prints everything at once (no `q` needed).

## 17.4 · Crash it: watch systemd restart it

```bash
systemctl show -p MainPID --value paysim
sudo kill -9 $(systemctl show -p MainPID --value paysim)
sleep 5
systemctl status paysim --no-pager
journalctl -u paysim -n 8 --no-pager
systemctl show -p NRestarts paysim
```

Sample lines (from the journal):

```text
systemd[1]: paysim.service: Main process exited, code=killed, status=9/KILL
systemd[1]: paysim.service: Failed with result 'signal'.
systemd[1]: paysim.service: Scheduled restart job, restart counter is at 1.
systemd[1]: Started paysim.service - PayBank payment simulator.
```

- `code=killed, status=9/KILL` = something sent SIGKILL (Topic 06).
- `restart counter is at 1` = systemd started it again, 3 s later (`RestartSec=3`).
- The **Main PID** is new after the restart.

| `Restart=` | Restarts when |
|---|---|
| `no` (default) | never |
| `on-failure` | crash, kill by signal, non-zero exit, timeout |
| `always` | every exit, even a clean one |

- **Stop vs crash:** `systemctl stop` is a clean stop: no restart.
- **Restart storm guard:** more than 5 starts in 10 seconds and systemd gives up (`Start request repeated too quickly`). Then fix the cause and run `sudo systemctl reset-failed paysim`.

## 17.5 · Change a setting safely: a drop-in file

- Never edit a package's unit file: an upgrade overwrites it.
- Put your changes in a **drop-in** folder `<name>.service.d/`. Files there override single lines.

```bash
sudo mkdir -p /etc/systemd/system/paysim.service.d
sudo tee /etc/systemd/system/paysim.service.d/override.conf > /dev/null <<'EOF'
[Service]
Environment=APP_ENV=prod
LimitNOFILE=4096
EOF
sudo systemctl daemon-reload
sudo systemctl restart paysim
systemctl cat paysim
systemctl show -p Environment paysim
journalctl -u paysim -n 1 --no-pager
```

- `systemctl cat` shows the main file **and** every drop-in, in the order systemd reads them.
- The log line now says `env=prod`: the later `Environment=APP_ENV` wins.
- `LimitNOFILE=4096` = this service may open 4096 files (Topic 18).
- `sudo systemctl edit paysim` opens an editor and creates the same `override.conf` for you.

## 17.6 · journalctl: find the right lines fast

```bash
journalctl -u paysim --no-pager | tail -n 5
journalctl -u paysim --since "15 minutes ago" --no-pager
journalctl -u paysim --since "$(date '+%F %H:00')" --until now --no-pager | tail -n 5
journalctl -u paysim -p warning --no-pager
journalctl -p err -b --no-pager | tail -n 10
journalctl -u paysim -o short-iso -n 3 --no-pager
journalctl -u cron -u paysim -n 6 --no-pager
journalctl --disk-usage
```

| Option | Means |
|---|---|
| `-u NAME` | only this unit (repeat `-u` for several) |
| `-n 20` | last 20 lines |
| `--since` / `--until` | time window: `"2026-08-24 09:10"`, `"1 hour ago"`, `today`, `yesterday` |
| `-p err` | priority **err and worse** |
| `-b` | since this boot (`-b -1` = previous boot) |
| `-o short-iso` | full date with time zone, good for reports |
| `-f` | follow live (`Ctrl+C` to stop) |
| `-k` | kernel messages only (same as `dmesg`) |

Priorities, most serious first:

| Number | Name | Example |
|---|---|---|
| 0–2 | `emerg` `alert` `crit` | disk failing, kernel problem |
| 3 | `err` | a service failed |
| 4 | `warning` | something odd, still working |
| 5–6 | `notice` `info` | normal events |
| 7 | `debug` | very detailed |

- `journalctl -p err -b` is a good **first look** on any server after a problem: every error since boot, all services.

## 17.7 · systemd timer: cron's modern replacement

A timer needs two files: a **service** that does the job once, and a **timer** that says when.

```bash
sudo tee /etc/systemd/system/paysim-health.service > /dev/null <<'EOF'
[Unit]
Description=Check paysim health once

[Service]
Type=oneshot
ExecStart=/usr/bin/curl -sf --max-time 5 http://127.0.0.1:8085/health
EOF
sudo tee /etc/systemd/system/paysim-health.timer > /dev/null <<'EOF'
[Unit]
Description=Check paysim health every minute

[Timer]
OnCalendar=minutely
Persistent=true

[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now paysim-health.timer
systemctl list-timers paysim-health.timer --no-pager
```

Wait a minute, then:

```bash
journalctl -u paysim-health -n 4 --no-pager
```

Sample lines:

```text
systemd[1]: Starting paysim-health.service - Check paysim health once...
curl[3051]: payment OK
systemd[1]: paysim-health.service: Deactivated successfully.
systemd[1]: Finished paysim-health.service - Check paysim health once.
```

| | cron | systemd timer |
|---|---|---|
| file | one line in a crontab | `.service` + `.timer` |
| output | lost unless you redirect it | in the journal, automatically |
| missed run (server was off) | skipped | `Persistent=true` runs it at boot |
| see next run | no | `systemctl list-timers` |
| `OnCalendar=` examples | | `minutely`, `hourly`, `daily`, `Mon..Fri 09:00`, `*-*-* 02:30` |

Stop the timer (keep paysim running: Topic 18 and 21 use it):

```bash
sudo systemctl disable --now paysim-health.timer
```

---

## Exercises

1. Change paysim's port to 8086 with a drop-in (not by editing the main file). Prove it with `ss` and `curl`.
2. After your change, `systemctl restart paysim` still uses 8085. What did you forget?
3. Kill paysim with `kill -9` three times. What is `NRestarts` now?
4. Show only paysim's journal lines from the last 5 minutes, with full ISO dates.
5. Show every `err`-or-worse message since boot, from all services.
6. Make the health timer run every 5 minutes instead of every minute.
7. Put the port back to 8085.

## Answers

1. Add `Environment=PORT=8086` to `override.conf`, then `sudo systemctl daemon-reload && sudo systemctl restart paysim`; `sudo ss -lntp | grep 8086`; `curl -s http://127.0.0.1:8086/health` → `payment OK`.
2. `sudo systemctl daemon-reload`.
3. The earlier count plus 3 (`systemctl show -p NRestarts paysim`).
4. `journalctl -u paysim --since "5 minutes ago" -o short-iso --no-pager`.
5. `journalctl -p err -b --no-pager`.
6. `OnCalendar=*:0/5` in the `.timer` file, then `daemon-reload` and `sudo systemctl restart paysim-health.timer`.
7. Remove the `PORT=8086` line from `override.conf`, `daemon-reload`, `restart`.
