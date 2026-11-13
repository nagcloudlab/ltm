# 21 · Troubleshooting scenarios: break it, read it, fix it

**Time:** 75 min · **Work:** in pairs

**Practise on** your own lab VM. **Needs:** paysim from Topic 17, the tools from Topics 18–20.

**How to work:**

- One person runs the **Break** block while the other looks away.
- The other person finds the cause using only the **Read** commands and the logs, says the cause out loud, then runs **Fix** and **Verify**.
- Swap roles for the next scenario.

**The method, every time:**

1. **Symptom:** what exactly fails? (`curl`, `systemctl status`, the error the user saw)
2. **Scope:** one service, one file, the whole server?
3. **Logs:** `journalctl -u NAME`, the app log, `syslog`, `auth.log`, `dmesg` (Topic 20.2)
4. **The exact line:** time, program, level, message, code
5. **Cause → fix → verify → write it down**

---

## Scenario 1 · The service will not start: `203/EXEC`

**Break**

```bash
sudo chmod 644 /opt/paysim/paysim.sh
sudo systemctl restart paysim
```

**Symptom**

- Wait a few seconds: `Restart=on-failure` keeps trying every 3 s, so the state jumps between `activating` and `failed`.

- `curl -s http://127.0.0.1:8085/health` prints nothing; `systemctl is-active paysim` says `activating` or `failed`.

**Read**

```bash
systemctl status paysim --no-pager
journalctl -u paysim -n 6 --no-pager
```

**Look for**

```text
paysim.service: Main process exited, code=exited, status=203/EXEC
```

- `203/EXEC` = systemd could not **run** the `ExecStart` file at all. The program never started, so it wrote nothing itself.
- Two usual causes: the path is wrong, or the file is not executable.

```bash
systemctl cat paysim | grep ExecStart
ls -l /opt/paysim/paysim.sh
```

**Cause:** `-rw-r--r--`: no `x`.

**Fix**

```bash
sudo chmod 755 /opt/paysim/paysim.sh
sudo systemctl reset-failed paysim
sudo systemctl restart paysim
```

**Verify**

```bash
systemctl is-active paysim
curl -s http://127.0.0.1:8085/health
```

| status= | Means |
|---|---|
| `203/EXEC` | could not run the program (path, `x` permission, wrong `#!` line) |
| `217/USER` | the `User=` does not exist |
| `200/CHDIR` | `WorkingDirectory=` does not exist |
| `1/FAILURE`, `2/…` | the program ran and exited with an error: **read its own lines** above |
| `9/KILL` | killed (by a person, or the OOM killer) |

## Scenario 2 · "Address already in use"

**Break** (something else grabs port 8085 while paysim is stopped)

```bash
sudo systemctl stop paysim
python3 -m http.server 8085 --bind 127.0.0.1 > /dev/null 2>&1 &
sleep 1
sudo systemctl start paysim
```

**Symptom**

- `curl -s http://127.0.0.1:8085/health` gets an answer, but not `payment OK`, and `systemctl is-active paysim` is not `active`. Someone else is answering on the port.

**Read**

```bash
systemctl status paysim --no-pager
journalctl -u paysim -n 10 --no-pager
sudo ss -ltnp '( sport = :8085 )'
```

**Look for**

```text
paysim.sh[2697]: OSError: [Errno 98] Address already in use
LISTEN 0  5  127.0.0.1:8085  0.0.0.0:*  users:(("python3",pid=2693,fd=3))
```

- `Errno 98` / `EADDRINUSE` / `Address already in use` = another process already listens on that port.
- `ss -p` names it: `python3`, PID 2693, owned by **you**, not by `www-data`.
- Apache says `(98)Address already in use: AH00072: make_sock: could not bind to address`; Tomcat says `java.net.BindException: Address already in use`. Same cause.

**Fix:** stop the other process **by its PID** (from `ss`), then start the service:

```bash
kill $(sudo ss -ltnp '( sport = :8085 )' | grep -o 'pid=[0-9]*' | cut -d= -f2)
sudo systemctl reset-failed paysim
sudo systemctl start paysim
```

> Do not use `pkill -f "http.server 8085"` here: `-f` also matches any shell whose command line contains those words, including the one running the `pkill`.

**Verify**

```bash
sudo ss -ltnp '( sport = :8085 )'
systemctl is-active paysim
```

`users:(("python3",pid=…))` and the PID equals `systemctl show -p MainPID --value paysim`.

## Scenario 3 · A typo in a setting

**Break**

```bash
printf '[Service]\nEnvironment=PORT=80B5\n' | sudo tee /etc/systemd/system/paysim.service.d/port.conf
sudo systemctl daemon-reload
sudo systemctl restart paysim
```

**Read**

```bash
journalctl -u paysim -n 8 --no-pager
systemctl cat paysim
```

**Look for**

```text
paysim.sh[3517]: paysim starting on port 80B5 (env=prod)
paysim.sh[3517]: server.py: error: argument port: invalid int value: '80B5'
paysim.service: Main process exited, code=exited, status=2/INVALIDARGUMENT
```

- This time the program **did** start and wrote its own complaint: read the lines **above** the systemd line.
- `systemctl cat` shows which file set `PORT=80B5`: the new `port.conf`.

**Fix**

```bash
sudo rm /etc/systemd/system/paysim.service.d/port.conf
sudo systemctl daemon-reload
sudo systemctl reset-failed paysim
sudo systemctl restart paysim
```

**Verify:** `curl -s http://127.0.0.1:8085/health` → `payment OK`.

## Scenario 4 · 404 for a file that exists (permissions)

**Break**

```bash
sudo chmod 600 /opt/paysim/health
```

**Symptom**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8085/health
ls -l /opt/paysim/health
```

- `404`, but `ls` shows the file is there.

**Read**

```bash
journalctl -u paysim -n 2 --no-pager
systemctl show -p User paysim
sudo -u www-data cat /opt/paysim/health
```

**Look for**

```text
paysim.sh[3563]: 127.0.0.1 - - [13/Nov/2026 00:42:43] code 404, message File not found
cat: /opt/paysim/health: Permission denied
```

- The service runs as `www-data`; the file is `rw-------` owned by `root`: www-data may not read it.
- Some servers report this as **403** (Apache, Nginx), this one as **404**. Always test as the service's user (Topic 05.3).

**Fix and verify**

```bash
sudo chmod 644 /opt/paysim/health
sudo -u www-data cat /opt/paysim/health
curl -s http://127.0.0.1:8085/health
```

## Scenario 5 · The app cannot write: disk full

**Break** (a 20 MB test disk as the app's log folder)

```bash
sudo mkdir -p /mnt/applogs
sudo mount -t tmpfs -o size=20M tmpfs /mnt/applogs
dd if=/dev/zero of=/mnt/applogs/old-dump.bin bs=1M count=25
```

**Symptom**

```bash
echo "$(date) payment ok" >> /mnt/applogs/app.log
```

**Look for**

```text
bash: echo: write error: No space left on device
```

**Read**

```bash
df -h /mnt/applogs
df -i /mnt/applogs
du -sh /mnt/applogs/* | sort -h
```

- `Use% 100%` in `df -h` → space. (If `df -h` were low and `df -i` 100%, it would be inodes: Topic 18.4.)
- `du` names the big file.

**Fix** (in real life: compress or move it, ask before deleting; Topic 07.2)

```bash
rm /mnt/applogs/old-dump.bin
echo "$(date) payment ok" >> /mnt/applogs/app.log
df -h /mnt/applogs
```

## Scenario 6 · Deleted, but the disk is still full

**Break**

```bash
fallocate -l 15M /mnt/applogs/live.log
tail -f /mnt/applogs/live.log > /dev/null &
sleep 1
rm /mnt/applogs/live.log
df -h /mnt/applogs
```

**Symptom:** the file is gone (`ls /mnt/applogs`), but `df` still shows the space used.

**Read**

```bash
sudo lsof +L1 | grep applogs
```

**Look for**

```text
tail  4120 student  3r  REG  0,61  15728640  0  2 /mnt/applogs/live.log (deleted)
```

- `(deleted)` + a process name and PID = the space is still held by that process.
- `$!` below = the PID of the last background job (the `tail`).

**Fix:** restart or stop the process holding it (here: the `tail`):

```bash
kill $!
df -h /mnt/applogs
```

Clean up the test disk:

```bash
sudo umount /mnt/applogs
```

## Scenario 7 · The cron job never ran

**Break** (a job written exactly as you would type it in the shell)

```bash
(crontab -l 2>/dev/null; echo '* * * * * echo "run $(date +%F)" >> $HOME/cron-test.log') | crontab -
crontab -l
```

- `crontab -l` prints the current list; `| crontab -` installs the new list. Same as editing with `crontab -e`.

Wait 2 minutes.

**Symptom**

```bash
ls -l ~/cron-test.log
```

`No such file or directory`.

**Read**

```bash
grep CRON /var/log/syslog | tail -n 4
```

**Look for**

```text
CRON[2664]: (student) CMD (echo "run $(date +)
CRON[2663]: (CRON) info (No MTA installed, discarding output)
```

- The `CMD` line proves cron **did** start the job, at the right minute.
- The command is **cut off** after `date +`: cron treats `%` as "end of command". (Topic 08.6.)
- `No MTA installed, discarding output` = the job printed an error and cron wanted to e-mail it, but there is no mail system: the error is lost. Always add `>> file 2>&1`.

**Fix**

```bash
crontab -l | grep -v cron-test | crontab -
(crontab -l 2>/dev/null; echo '* * * * * echo "run $(date +\%F)" >> $HOME/cron-test.log 2>&1') | crontab -
crontab -l
```

**Verify** (after 2 minutes):

```bash
cat ~/cron-test.log
```

Clean up:

```bash
crontab -l | grep -v cron-test | crontab -
```

## Scenario 8 · ssh key login suddenly asks for a password

**Prepare** (key login to your own machine, Topic 13):

```bash
ls ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new localhost hostname
```

- `BatchMode=yes` = never ask for a password: fail instead. Good for tests and scripts.

**Break**

```bash
chmod 777 ~/.ssh
```

**Symptom**

```bash
ssh -o BatchMode=yes localhost hostname
```

`Permission denied (publickey,password).`

**Read**

```bash
sudo grep sshd /var/log/auth.log | tail -n 5
```

**Look for**

```text
sshd[2526]: Authentication refused: bad ownership or modes for directory /home/student/.ssh
```

- The **client** only says "Permission denied". The **server's** `auth.log` says why: sshd ignores keys in a folder others can write to.

**Fix and verify**

```bash
chmod 700 ~/.ssh
ssh -o BatchMode=yes localhost hostname
```

## Scenario 9 · Memory: the service died with nothing in its log

**Break**

```bash
sudo systemd-run --unit=reportjob -p MemoryMax=50M -p MemorySwapMax=0 python3 -c "x = bytearray(200*1024*1024)"
sleep 2
```

**Read**

```bash
systemctl status reportjob --no-pager
sudo dmesg -T | grep -i "killed process" | tail -n 1
```

**Look for**

```text
Active: failed (Result: oom-kill)
Memory cgroup out of memory: Killed process 93243 (python3) …
```

- The program had no chance to write anything: the kernel stopped it with SIGKILL.
- **Fix** depends on the cause: give it more memory (`MemoryMax=`, or a bigger `-Xmx` for Java), or find the leak (developers).

```bash
sudo systemctl reset-failed reportjob
```

## Scenario 10 · Mixed drill (trainer or partner)

The partner picks **two** Break blocks from scenarios 1–8 and runs them together, without saying which. You get only this message:

> *"paysim is down and the nightly job didn't run. Fix it."*

- Use the method at the top. Write each finding as: **time · log · line · cause · fix · verified how**.

---

## Quick reference: message → first command

| You see | Run first |
|---|---|
| `status=203/EXEC` | `systemctl cat NAME \| grep ExecStart` and `ls -l` that file |
| `Address already in use` | `sudo ss -ltnp '( sport = :PORT )'` |
| `Permission denied` / 403 / 404 on an existing file | `sudo -u SERVICEUSER cat FILE`, `ls -l`, `ls -ld` each folder |
| `No space left on device` | `df -h` then `df -i` |
| space not freed after `rm` | `sudo lsof +L1` |
| `Too many open files` | `/proc/PID/limits`, `ls /proc/PID/fd \| wc -l` |
| `Result: oom-kill`, app vanished | `sudo dmesg -T \| grep -i "killed process"` |
| cron job silent | `grep CRON /var/log/syslog`, look for the cut `CMD` and `No MTA` |
| ssh key ignored | `sudo grep sshd /var/log/auth.log` |
| wrong IP for a name | `getent hosts NAME`, `/etc/hosts` |

---

## Exercises

1. A unit shows `status=217/USER`. What is wrong?
2. `ss` shows port 8080 owned by `java` PID 900, but `systemctl show -p MainPID --value tomcat` is 0. What happened?
3. Why does the cron `CMD` line in syslog look cut off, and what tells you the error was lost?
4. An app returns 404 for `/opt/app/files/a.pdf`, which exists. Give the first two commands.
5. `ssh` with a key fails only for one user. Which log, which line?

## Answers

1. The `User=` in the unit does not exist (`id NAME` to check).
2. An old Tomcat (started by hand, outside systemd) still holds the port, so the service could not start: `Address already in use` in `journalctl -u tomcat`. Stop PID 900, then start the service.
3. An unescaped `%` ends the command; `No MTA installed, discarding output`.
4. `systemctl show -p User APP` (who runs it), then `sudo -u THATUSER cat /opt/app/files/a.pdf` (and `ls -ld` each folder).
5. `/var/log/auth.log` on the **server**: `Authentication refused: bad ownership or modes …`.
