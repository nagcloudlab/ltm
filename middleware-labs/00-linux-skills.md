# Lab 0 — Linux skills for middleware administrators

- **Needs:** [student start](00-student-start.md) completed on your Ubuntu 24.04 laptop
- **You build:** the basic skills every later lab uses — files, vi, permissions, processes, ports, services, logs and verified backups, with built-in Ubuntu tools

- Run every command as your normal account; use `sudo` only where shown.
- Everything you create lives under `~/lab`. No system files are changed.
- An unexpected error? Stop and read it first — reading errors is a core skill.

## 1. Who and where am I?

- Know which account you are and which folder you are in before you change anything.

Show your user name:

```bash
whoami
```

Show your user number and groups:

```bash
id
```

Show the machine name:

```bash
hostname
```

Show the current folder:

```bash
pwd
```

Show date and time:

```bash
date
```

- A new terminal starts in your home folder, `/home/<your-name>`; `~` is short for it.

## 2. Move around the file system

List files:

```bash
ls
```

Long listing (type, permissions, owner, group, size, date, name):

```bash
ls -l
```

Include hidden files (names starting with `.`, e.g. `.bashrc`):

```bash
ls -la
```

Human-readable sizes:

```bash
ls -lh /etc/hostname /etc/hosts
```

Go to `/etc`:

```bash
cd /etc
```

Check where you are:

```bash
pwd
```

Go home:

```bash
cd ~
```

Check again:

```bash
pwd
```

Go back to the previous folder:

```bash
cd -
```

Go home (short form):

```bash
cd
```

- **Absolute path** starts with `/` (`/etc/hosts`); **relative path** starts from where you are (`lab/evidence`).

Show a folder structure (`tree` is not always installed):

```bash
find ~/lab -maxdepth 2
```

Same, recursively with `ls`:

```bash
ls -R ~/lab
```

## 3. The middleware directory map

- Folders you use in every lab. Some do not exist until the software is installed.

| Path | What lives there | Example in these labs |
| --- | --- | --- |
| `/etc` | Configuration | `/etc/apache2`, `/etc/nginx`, `/etc/kong-lab`, `/etc/hosts` |
| `/etc/systemd/system` | Admin-added service (unit) files | `tomcat.service`, `payment-kong.service` |
| `/var/log` | Logs | `/var/log/apache2`, `/var/log/nginx`, `/var/log/kong-lab` |
| `/var/www` | Web content | `/var/www/payment-portal` |
| `/opt` | Software installed by hand | `/opt/tomcat` |
| `/usr/lib/jvm` | Java installations | `/usr/lib/jvm/java-21-lab` |
| `~/lab` | Your evidence, backups, practice files | `~/lab/evidence`, `~/lab/backups` |

Show the folders themselves (`-d`), not their contents:

```bash
ls -ld /etc /var/log /opt /home
```

Check the folders created in later labs:

```bash
ls -ld /var/www /usr/lib/jvm /opt/tomcat
```

- **Expected:** `No such file or directory` for some paths before Labs 1 and 3. The message names the exact missing path.

List the log folders:

```bash
ls /var/log
```

## 4. Create, copy, move and remove files

- Build a harmless practice area.

Create folders (`-p` adds missing parents, no error if they exist):

```bash
mkdir -p ~/lab/practice/conf ~/lab/practice/logs ~/lab/practice/old
```

Enter it:

```bash
cd ~/lab/practice
```

Create an empty file:

```bash
touch notes.txt
```

Write a line (`>` **replaces** the content):

```bash
echo "first line" > notes.txt
```

Append a line (`>>` **adds** to the end):

```bash
echo "second line" >> notes.txt
```

Show the file:

```bash
cat notes.txt
```

Count lines:

```bash
wc -l notes.txt
```

- Mixing up `>` and `>>` is a classic way to lose a config file.

Copy a file:

```bash
cp notes.txt notes.bak
```

Copy a folder with permissions and dates (use for backups):

```bash
cp -a conf conf-copy
```

Move a file:

```bash
mv notes.bak old/
```

Rename (same command):

```bash
mv conf-copy conf-renamed
```

Check both folders:

```bash
ls -l . old
```

Remove a file — there is no recycle bin, read the path twice:

```bash
rm old/notes.bak
```

Remove an empty folder (refuses if it still has files):

```bash
rmdir conf-renamed
```

Check:

```bash
ls -la
```

Look at files without an editor — first lines:

```bash
head -n 3 /etc/passwd
```

Last lines:

```bash
tail -n 3 /etc/passwd
```

File type:

```bash
file /etc/hosts /usr/bin/ls
```

Size, permissions and dates:

```bash
stat notes.txt
```

## 5. Edit a file with vi

- Servers often have no graphical editor; `vi` (on Ubuntu, `vim`) is always there.

Go to the conf folder:

```bash
cd ~/lab/practice/conf
```

Create a practice config:

```bash
printf 'name=payment\nport=8080\nlog_level=INFO\ntimeout=10\n' > app.conf
```

Show it:

```bash
cat app.conf
```

- **Normal mode** (start): keys are commands. **Insert mode**: keys type text — `i` enters, `Esc` leaves.

| Keys (normal mode) | Action |
| --- | --- |
| `i` / `Esc` | Insert mode / back to normal mode |
| `:w` / `:q` / `:wq` + Enter | Save / quit / save and quit |
| `:q!` + Enter | Quit **without** saving |
| `/port` + Enter, then `n` | Search, next match |
| `u` / `dd` / `yy` then `p` | Undo / delete line / copy line and paste below |
| `gg` / `G` / `:set number` | First line / last line / line numbers |

Open the file:

```bash
vi ~/lab/practice/conf/app.conf
```

- Type `/port` + Enter to jump to the port line.
- Arrow onto `8080`, press `i`, change it to `8090`, press `Esc`.
- `dd` on the `timeout=10` line, then `u` to undo.
- `:wq` + Enter.

Check the edit:

```bash
grep -n 'port' ~/lab/practice/conf/app.conf
```

- **Expected:** `2:port=8090`.
- **If lost in vi:** `Esc` twice, then `:q!` — leave without saving and start again.

## 6. Permissions and ownership

Go to the conf folder:

```bash
cd ~/lab/practice/conf
```

Show permissions:

```bash
ls -l app.conf
```

- Sample output:

```text
-rw-rw-r-- 1 student student 49 Nov 11 10:05 app.conf
```

- First character: `-` file, `d` directory, `l` link.
- Then `rwx` for **owner**, **group**, **others**. On a directory, `x` = may enter / pass through.
- Then owner (`student`) and group (`student`).
- Numbers: `r=4`, `w=2`, `x=1`, added per group. `640` = owner `rw-`, group `r--`, others `---`.

Set 640:

```bash
chmod 640 app.conf
```

Check:

```bash
ls -l app.conf
```

Add read for others:

```bash
chmod o+r app.conf
```

Check:

```bash
ls -l app.conf
```

Add execute for owner, remove read for group:

```bash
chmod u+x,g-r app.conf
```

Check:

```bash
ls -l app.conf
```

Back to 644:

```bash
chmod 644 app.conf
```

Check:

```bash
ls -l app.conf
```

| Mode | Used for |
| --- | --- |
| `644` | Normal readable files (web pages, configs) |
| `640` | Owner + one group only (password files) |
| `755` | Folders and scripts everyone may enter or run |
| `750` | Folders for owner + one group only (`/opt/tomcat`) |

Give the file to root (ownership changes need `sudo`):

```bash
sudo chown root:root app.conf
```

Check:

```bash
ls -l app.conf
```

Try to append:

```bash
echo "extra=1" >> app.conf
```

- **Expected:** `Permission denied` — root owns it, others may only read.

Give it back to you:

```bash
sudo chown "$USER:$USER" app.conf
```

Check:

```bash
ls -l app.conf
```

- A file is readable only if **every folder on the path** can be entered.

Show permissions of each step of the path:

```bash
namei -l ~/lab/practice/conf/app.conf
```

Try to read it as the web server user:

```bash
sudo -u www-data cat ~/lab/practice/conf/app.conf
```

- **Expected:** `Permission denied`. Ubuntu 24.04 home folders are `drwxr-x---` (750); `www-data` is "others" and cannot pass through. That is why web content lives in `/var/www`.

- `umask` decides the permissions of new files.

Show the umask:

```bash
umask
```

Create a file:

```bash
touch new-file.txt
```

Create a folder:

```bash
mkdir new-dir
```

Compare:

```bash
ls -ld new-file.txt new-dir
```

- `umask 0002` (desktop users): files `664`, folders `775`. `0022` (servers): `644` and `755`.
- Tomcat and Kong unit files in later labs set `UMask=0027`, so their new logs are not readable by others.

## 7. Users, groups and sudo

Show your account:

```bash
id
```

Show your groups:

```bash
groups
```

Show the root account entry:

```bash
getent passwd root
```

Show the web server account:

```bash
getent passwd www-data
```

Show members of the `sudo` group:

```bash
getent group sudo
```

List what you may run with sudo:

```bash
sudo -l
```

- `/etc/passwd` format: `name:x:uid:gid:comment:home:shell`. Service accounts like `www-data` have `/usr/sbin/nologin`: they run software, nobody logs in.
- `sudo` group members may run commands as root.
- `sudo -u <user> <command>` runs one command as another user — later labs use it to check "can the service user read this file?".

## 8. Processes

- Every program is a **process** with a PID and a PPID (parent's PID).

All processes, first lines:

```bash
ps -ef | head -n 15
```

Chosen columns, busiest CPU first:

```bash
ps -eo pid,ppid,user,%cpu,%mem,cmd --sort=-%cpu | head -n 10
```

Find processes by name:

```bash
pgrep -a systemd
```

One `top` snapshot (batch mode, can be saved as evidence):

```bash
top -b -n 1 | head -n 15
```

- Plain `top` is interactive: `P` sort by CPU, `M` by memory, `q` quit.

Start a harmless background process (`&`):

```bash
sleep 600 &
```

List this terminal's background jobs:

```bash
jobs
```

Find it:

```bash
pgrep -a sleep
```

Ask it to stop cleanly:

```bash
kill -TERM "$(pgrep -n -x sleep)"
```

Check it is gone:

```bash
jobs
```

- `kill -TERM` (15, default): stop cleanly, close files. `kill -KILL` (9): immediate, no clean-up — only if `TERM` fails. `systemctl stop` sends `TERM` first.

Start a process with lower priority (`nice`):

```bash
nice -n 10 sleep 30 &
```

Show its priority:

```bash
ps -o pid,ni,cmd -p "$(pgrep -n -x sleep)"
```

- **Expected:** `NI` column shows `10`.

Stop it:

```bash
kill "$(pgrep -n -x sleep)"
```

## 9. Memory, disk and load

Memory:

```bash
free -h
```

- Read **available**, not **free** — Linux uses spare memory as cache.

Disk space per file system:

```bash
df -h
```

Space where logs live:

```bash
df -h /var/log
```

- If the `/var/log` file system hits 100 %, services cannot write logs and may fail.

Size of one folder:

```bash
du -sh ~/lab
```

Size of the log folder:

```bash
sudo du -sh /var/log
```

Load averages (1, 5, 15 min):

```bash
uptime
```

Number of CPU cores:

```bash
nproc
```

- Load near or above the core count = machine is busy.

## 10. Services with systemd

- Each long-running server program is a **service** (systemd unit). Practise on `cron`.

Full status:

```bash
systemctl status cron --no-pager
```

Running now?

```bash
systemctl is-active cron
```

Starts at boot?

```bash
systemctl is-enabled cron
```

All running services:

```bash
systemctl list-units --type=service --state=running --no-pager
```

Failed units — check this first when something "stopped working":

```bash
systemctl list-units --failed --no-pager
```

Last 20 log lines of a service:

```bash
sudo journalctl -u cron -n 20 --no-pager
```

Last hour only:

```bash
sudo journalctl -u cron --since '1 hour ago' --no-pager
```

Errors since last boot:

```bash
sudo journalctl -p err -b --no-pager | tail -n 20
```

- `-u` unit, `-n` lines, `--since` time window, `-p err` errors only, `-b` since boot.
- `sudo journalctl -u cron -f` follows live; Ctrl+C stops.
- Later: `sudo systemctl start|stop|restart|reload <name>`. `reload` re-reads config without dropping connections, if supported.

## 11. Ports and networking

Interfaces and addresses (`lo` / `127.0.0.1` = this laptop):

```bash
ip -br a
```

Routes (`default via` = gateway):

```bash
ip route
```

Listening TCP ports with process:

```bash
sudo ss -lntp
```

- `0.0.0.0:80` = all addresses; `127.0.0.1:8080` = local only.

Local name table:

```bash
cat /etc/hosts
```

Resolve a name like most programs do (`/etc/hosts`, then DNS — no `dig` needed):

```bash
getent hosts localhost
```

Resolve an internet name:

```bash
getent ahosts ubuntu.com
```

Ping loopback:

```bash
ping -c 3 127.0.0.1
```

Ping an internet host (some networks block ping; then use curl):

```bash
ping -c 3 ubuntu.com
```

- Ping proves the network path and name, not that a web server works.

Response headers only (first line = status):

```bash
curl -I https://ubuntu.com/
```

Save the body and print status and time:

```bash
curl -s -o ~/lab/practice/ubuntu-home.html -w 'status=%{http_code} time=%{time_total}s\n' https://ubuntu.com/
```

Download with wget:

```bash
wget -O ~/lab/practice/ubuntu-home-wget.html https://ubuntu.com/
```

Check the downloads:

```bash
ls -lh ~/lab/practice/*.html
```

- `curl -v` prints every step (lookup, connect, headers) — use it when you do not know where a request fails.

- Run your own small web server on a test port.

Go to the practice folder:

```bash
cd ~/lab/practice
```

Start a test server in the background:

```bash
python3 -m http.server 8099 --bind 127.0.0.1 &
```

Wait a second:

```bash
sleep 1
```

Who listens on 8099?

```bash
sudo ss -lntp 'sport = :8099'
```

Headers:

```bash
curl -I http://127.0.0.1:8099/notes.txt
```

Every step of the request:

```bash
curl -v http://127.0.0.1:8099/notes.txt
```

Test the TCP port only:

```bash
nc -zv 127.0.0.1 8099
```

Test a port where nothing listens:

```bash
nc -zv 127.0.0.1 8098
```

- **Expected:** `succeeded` for 8099; `Connection refused` for 8098.

Stop the test server (matches the full command line):

```bash
pkill -f 'http.server 8099'
```

## 12. Search and summarise logs

- Generate a sample access log in the "combined" format Apache and Nginx use later.

Go to the logs folder:

```bash
cd ~/lab/practice/logs
```

Generate 200 lines:

```bash
for i in $(seq 1 200); do
  ip="10.0.0.$(( i % 7 + 1 ))"
  status=200; path=/index.html
  if [ $(( i % 10 )) -eq 0 ]; then status=404; path=/missing.html; fi
  if [ $(( i % 25 )) -eq 0 ]; then status=500; path=/payment/fail; fi
  if [ $(( i % 33 )) -eq 0 ]; then status=401; path=/admin/; fi
  printf '%s - - [11/Nov/2026:10:%02d:%02d +0530] "GET %s HTTP/1.1" %s %s "-" "curl/8.5.0"\n' \
    "$ip" $(( i / 60 )) $(( i % 60 )) "$path" "$status" $(( 100 + i ))
done > access.log
```

Count lines:

```bash
wc -l access.log
```

First lines:

```bash
head -n 3 access.log
```

- Sample line:

```text
10.0.0.2 - - [11/Nov/2026:10:00:01 +0530] "GET /index.html HTTP/1.1" 200 101 "-" "curl/8.5.0"
```

Count 404s:

```bash
grep -c '" 404 ' access.log
```

500s with line numbers:

```bash
grep -n '" 500 ' access.log
```

Ignore case:

```bash
grep -i 'ADMIN' access.log
```

Count lines that are **not** 200:

```bash
grep -v '" 200 ' access.log | wc -l
```

401 or 500 (extended pattern):

```bash
grep -E '" (401|500) ' access.log | tail -n 3
```

- `" 404 ` (quote, space, code, space) matches the status field, not a size or time containing `404`.
- awk fields here: `$1` client address, `$7` path, `$9` status.

Count per status:

```bash
awk '{print $9}' access.log | sort | uniq -c | sort -rn
```

Top three clients:

```bash
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -n 3
```

Server errors with time and path:

```bash
awk '$9 >= 500 {print $4, $7, $9}' access.log
```

Paths that gave 404:

```bash
awk '$9 == 404 {print $7}' access.log | sort | uniq -c
```

- **Expected status counts:** `170` × 200, `16` × 404, `8` × 500, `6` × 401.
- `sort | uniq -c | sort -rn` is the most-used log pipeline: group, count, biggest first.

Follow the log live (terminal A):

```bash
tail -f ~/lab/practice/logs/access.log
```

Append a line (terminal B):

```bash
echo '10.0.0.9 - - [11/Nov/2026:10:05:00 +0530] "GET /live-test HTTP/1.1" 404 120 "-" "curl/8.5.0"' >> ~/lab/practice/logs/access.log
```

- **Expected:** the line appears in terminal A at once. Ctrl+C stops `tail -f`.

Page through a long file:

```bash
less ~/lab/practice/logs/access.log
```

- Space next page, `b` back, `/500` + Enter search, `n` next match, `G` end, `q` quit.

## 13. Archives and checksums

Go to `~/lab`:

```bash
cd ~/lab
```

Create a dated backup archive:

```bash
tar czf ~/lab/backups/practice-$(date +%F).tar.gz -C ~/lab practice
```

Check it:

```bash
ls -lh ~/lab/backups/
```

List its contents — always before extracting:

```bash
tar tzf ~/lab/backups/practice-$(date +%F).tar.gz | head
```

Create a restore folder:

```bash
mkdir -p ~/lab/restore
```

Extract there:

```bash
tar xzf ~/lab/backups/practice-$(date +%F).tar.gz -C ~/lab/restore
```

Compare with the original:

```bash
diff -r ~/lab/practice ~/lab/restore/practice && echo "restore matches"
```

- `c` create, `t` list, `x` extract, `z` gzip, `f` archive name. `-C` changes folder first, so the archive stores `practice/...`, not your full home path.

- Zip files — a Java WAR is a zip file.

Install zip:

```bash
sudo apt install -y zip
```

Go to `~/lab`:

```bash
cd ~/lab
```

Zip the practice folder:

```bash
zip -r ~/lab/backups/practice.zip practice
```

List the zip:

```bash
unzip -l ~/lab/backups/practice.zip | tail -n 5
```

List the payment WAR:

```bash
unzip -l ~/ltm/middleware-labs/project-files/apps/payment.war
```

- Checksums prove a file was not changed or damaged.

Go to the backups:

```bash
cd ~/lab/backups
```

Record checksums:

```bash
sha256sum practice-*.tar.gz practice.zip > SHA256SUMS
```

Show them:

```bash
cat SHA256SUMS
```

Verify:

```bash
sha256sum -c SHA256SUMS
```

Damage the zip:

```bash
echo "tamper" >> practice.zip
```

Verify again:

```bash
sha256sum -c SHA256SUMS
```

- **Expected:** first check `OK` for every file; after the `echo`, the zip reports `FAILED` — one changed byte changes the checksum. Student start uses the same check.

- Rebuild the damaged zip and record new checksums.

Remove it:

```bash
rm ~/lab/backups/practice.zip
```

Go to `~/lab`:

```bash
cd ~/lab
```

Zip again quietly:

```bash
zip -r -q ~/lab/backups/practice.zip practice
```

Go to the backups:

```bash
cd ~/lab/backups
```

Record new checksums:

```bash
sha256sum practice-*.tar.gz practice.zip > SHA256SUMS
```

Verify:

```bash
sha256sum -c SHA256SUMS
```

## 14. Break it, find it

- Each scenario creates a small fault under `~/lab`, finds it, and removes it. Do them in order.

### Scenario A — "No space left on device"

**Break** — a 20 MB test disk, overfilled:

```bash
mkdir -p ~/lab/smalldisk
```

```bash
sudo mount -t tmpfs -o size=20M tmpfs ~/lab/smalldisk
```

```bash
sudo chown "$USER:$USER" ~/lab/smalldisk
```

```bash
df -h ~/lab/smalldisk
```

```bash
fallocate -l 15M ~/lab/smalldisk/old-app.log
```

```bash
fallocate -l 10M ~/lab/smalldisk/new-app.log
```

**Expected** — sample line:

```text
fallocate: fallocate failed: No space left on device
```

**Observe** — which file system is full:

```bash
df -h ~/lab/smalldisk
```

Which files fill it:

```bash
du -sh ~/lab/smalldisk/* | sort -h
```

- On a real server: `sudo du -sh /var/log/* | sort -h`.
- Fix: remove or archive the oldest log — never a file a running service still writes to without checking.

**Recover** — remove the old log:

```bash
rm ~/lab/smalldisk/old-app.log
```

**Verify:**

```bash
df -h ~/lab/smalldisk
```

Remove the test disk:

```bash
sudo umount ~/lab/smalldisk
```

```bash
rmdir ~/lab/smalldisk
```

### Scenario B — a runaway process

**Break** — `yes` uses a whole CPU core:

```bash
yes > /dev/null &
```

**Observe:**

```bash
top -b -n 1 | head -n 12
```

```bash
ps -eo pid,user,%cpu,cmd --sort=-%cpu | head -n 5
```

- **Expected:** `yes` at the top of both lists near 100 % CPU; `uptime` load rises over the next minute.

**Recover:**

```bash
kill -TERM "$(pgrep -x yes)"
```

**Verify:**

```bash
pgrep -a yes || echo "no yes process left"
```

### Scenario C — port already in use

**Break** — go to the practice folder:

```bash
cd ~/lab/practice
```

Start the first server:

```bash
python3 -m http.server 8099 --bind 127.0.0.1 &
```

```bash
sleep 1
```

Start a second one on the same port:

```bash
python3 -m http.server 8099 --bind 127.0.0.1
```

**Expected** — sample line:

```text
OSError: [Errno 98] Address already in use
```

- Same thing happens when Apache and Nginx both want port 80.

**Observe** — who owns the port:

```bash
sudo ss -lntp 'sport = :8099'
```

- Sample line:

```text
LISTEN 0      5          127.0.0.1:8099      0.0.0.0:*    users:(("python3",pid=4321,fd=3))
```

**Recover:**

```bash
pkill -f 'http.server 8099'
```

**Verify:**

```bash
sudo ss -lntp 'sport = :8099'
```

- **Expected:** only the header line.

### Scenario D — permission denied

**Break** — a file with no permissions:

```bash
cd ~/lab/practice/conf
```

```bash
chmod 000 app.conf
```

**Observe:**

```bash
ls -l app.conf
```

```bash
cat app.conf
```

**Expected** — sample line:

```text
cat: app.conf: Permission denied
```

- `----------`: only root may read it, not even you as owner.

**Recover:**

```bash
chmod 644 app.conf
```

**Verify:**

```bash
cat app.conf
```

**Break** — a folder that cannot be passed through:

```bash
chmod 600 ~/lab/practice/conf
```

**Observe:**

```bash
cat ~/lab/practice/conf/app.conf
```

```bash
namei -l ~/lab/practice/conf/app.conf
```

- Sample output:

```text
f: /home/student/lab/practice/conf/app.conf
drwxr-xr-x root    root    /
drwxr-xr-x root    root    home
drwxr-x--- student student student
drwxrwxr-x student student lab
drwxrwxr-x student student practice
drw------- student student conf
                            app.conf - Permission denied
```

- The file is still `644`, but `conf` lost its `x` bit; `namei -l` points at the exact folder. Same check as for an Apache 403 in Lab 1.

**Recover:**

```bash
chmod 755 ~/lab/practice/conf
```

**Verify:**

```bash
cat ~/lab/practice/conf/app.conf
```

### Scenario E — "Could not resolve host"

**Observe:**

```bash
curl -I http://lab0.example.test/
```

```bash
getent hosts lab0.example.test || echo "name not found"
```

**Expected** — sample line:

```text
curl: (6) Could not resolve host: lab0.example.test
```

- No server was reached: the **name** has no address. Different from `Connection refused` (address found, nothing listening) and from an HTTP error code (a server answered).
- In Lab 1 you fix this for `portal.example.test` with one line in `/etc/hosts`.

## 15. Self-check

Answer from memory, then check with a command.

1. Which command shows the permissions of a folder itself, not its contents?
2. A file is `-rw-r-----  root www-data`. Can `www-data` read it? Write it? Can your own account read it?
3. `kill -TERM` vs `kill -KILL`?
4. `free -h` shows `free 200Mi`, `available 2.1Gi`. Out of memory?
5. Which command shows the program listening on port 8099?
6. Write a pipeline printing the top three client addresses in `access.log`.
7. How do you prove a backup archive was not changed since you made it?
8. `curl` says `Connection refused` on port 8080: name problem, network problem or "nothing listening"?

Answers:

1. `ls -ld <folder>`.
2. Yes (group `r`); no (no group `w`); no — you are "others" with no permissions (unless `sudo`).
3. `TERM` asks for a clean finish; `KILL` ends at once without clean-up. Try `TERM` first.
4. No. `available` is what programs can use; much of the rest is cache given back when needed.
5. `sudo ss -lntp 'sport = :8099'`.
6. `awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -n 3`.
7. Record `sha256sum` when you make it; later run `sha256sum -c`.
8. Nothing listening: the name resolved and the laptop answered, but no program accepted the connection.

## 16. Clean up

No test web server left:

```bash
pgrep -af 'http.server 8099' || echo "no test web server left"
```

No `yes` process left:

```bash
pgrep -ax yes || echo "no yes process left"
```

Check your lab folder:

```bash
ls ~/lab
```

- Keep `~/lab/practice` — Lab 6 reuses the same log commands.
- Next: [Lab 1 — Apache](01-apache.md).
