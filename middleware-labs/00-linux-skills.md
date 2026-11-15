# Lab 0 — Linux skills for middleware administrators

**Time:** 60–75 minutes. **Prerequisite:** [student start](00-student-start.md) completed on your Ubuntu 24.04 laptop. **Deliverable:** you can move around the file system, edit a file with vi, read permissions, find processes, ports and services, search logs and make a verified backup — all with built-in Ubuntu tools.

Every later lab uses these commands. You practise here on harmless files under `~/lab/practice`, before any web server or application server is installed.

- Run every command as your normal account. Use `sudo` only where it is shown.
- Everything you create in this lab lives under `~/lab`. You never delete or change system files here.
- If a command prints an error you did not expect, stop and read the error first. Reading error messages is a core skill.

## 1. Who and where am I?

```bash
whoami
id
hostname
pwd
date
```

- `whoami` prints your user name; `id` adds your user number and groups.
- `pwd` (print working directory) shows the folder you are in. A new terminal starts in your home folder, `/home/<your-name>`.
- `~` is a short way of writing your home folder.

## 2. Move around the file system

```bash
ls
ls -l
ls -la
ls -lh /etc/hostname /etc/hosts
cd /etc
pwd
cd ~
pwd
cd -
cd
```

- `ls -l` shows the long listing: type and permissions, owner, group, size, date and name.
- `ls -a` also shows hidden files, whose names start with a dot (for example `.bashrc`).
- `cd -` goes back to the previous folder; `cd` on its own goes home.
- An **absolute path** starts with `/` (`/etc/hosts`). A **relative path** starts from where you are (`lab/evidence`).

The `tree` command is not always installed. These built-in commands show a folder structure instead:

```bash
find ~/lab -maxdepth 2
ls -R ~/lab
```

## 3. The middleware directory map

These are the folders you will use in every lab. Some of them do not exist yet because the software is not installed.

| Path | What lives there | Example in these labs |
| --- | --- | --- |
| `/etc` | Configuration files | `/etc/apache2`, `/etc/nginx`, `/etc/kong-lab`, `/etc/hosts` |
| `/etc/systemd/system` | Service (unit) files added by an administrator | `tomcat.service`, `payment-kong.service` |
| `/var/log` | Log files | `/var/log/apache2`, `/var/log/nginx`, `/var/log/kong-lab` |
| `/var/www` | Web content | `/var/www/payment-portal` |
| `/opt` | Software installed by hand, outside the package manager | `/opt/tomcat` |
| `/usr/lib/jvm` | Java installations | `/usr/lib/jvm/java-21-lab` |
| `~/lab` | Your own evidence, backups and practice files | `~/lab/evidence`, `~/lab/backups` |

```bash
ls -ld /etc /var/log /opt /home
ls -ld /var/www /usr/lib/jvm /opt/tomcat
ls /var/log
```

- The second command may print `No such file or directory` for some paths. That is expected before Labs 1 and 3. Read the message: it names the exact path that is missing.
- `ls -ld` shows the folder itself, not its contents.

## 4. Create, copy, move and remove files

Build a practice area:

```bash
mkdir -p ~/lab/practice/conf ~/lab/practice/logs ~/lab/practice/old
cd ~/lab/practice
touch notes.txt
echo "first line" > notes.txt
echo "second line" >> notes.txt
cat notes.txt
wc -l notes.txt
```

- `mkdir -p` creates the folder and any missing parent folders, and does not complain if it already exists.
- `>` **replaces** a file's content. `>>` **adds** to the end. Mixing them up is a classic way to lose a config file.

```bash
cp notes.txt notes.bak
cp -a conf conf-copy
mv notes.bak old/
mv conf-copy conf-renamed
ls -l . old
rm old/notes.bak
rmdir conf-renamed
ls -la
```

- `cp -a` copies a folder with its permissions and dates. Use it for backups.
- `mv` both moves and renames.
- `rm` has no recycle bin. Before you run it, read the path twice. Use `rmdir` for empty folders: it refuses to remove a folder that still has files.

Look at files without opening an editor:

```bash
head -n 3 /etc/passwd
tail -n 3 /etc/passwd
file /etc/hosts /usr/bin/ls
stat notes.txt
```

## 5. Edit a file with vi

On a server there is often no graphical editor. `vi` (on Ubuntu, `vim`) is always there. Create a practice config file:

```bash
cd ~/lab/practice/conf
printf 'name=payment\nport=8080\nlog_level=INFO\ntimeout=10\n' > app.conf
cat app.conf
```

vi has two main modes:

- **Normal mode** (where you start): keys are commands, not text.
- **Insert mode**: keys type text. Press `i` to enter it and `Esc` to leave it.

| Keys (in normal mode) | What they do |
| --- | --- |
| `i` | Start typing before the cursor (insert mode) |
| `Esc` | Back to normal mode |
| `:w` then Enter | Save (write) |
| `:q` then Enter | Quit |
| `:wq` then Enter | Save and quit |
| `:q!` then Enter | Quit **without** saving |
| `/port` then Enter | Search for `port`; `n` finds the next match |
| `u` | Undo the last change |
| `dd` | Delete the current line |
| `yy` then `p` | Copy the line, then paste it below |
| `gg` / `G` | Go to the first / last line |
| `:set number` | Show line numbers |

Practice task:

```bash
vi ~/lab/practice/conf/app.conf
```

- Type `/port` and Enter to jump to the port line.
- Move the cursor onto `8080` with the arrow keys, press `i`, change the value to `8090`, press `Esc`.
- Press `dd` on the `timeout=10` line, then `u` to undo it.
- Type `:wq` and Enter.

Check your edit without opening the file again:

```bash
grep -n 'port' ~/lab/practice/conf/app.conf
```

Expected: `2:port=8090`. If you get lost in vi, press `Esc` twice and type `:q!` — you leave without saving and can start again.

## 6. Permissions and ownership

```bash
cd ~/lab/practice/conf
ls -l app.conf
```

Sample output:

```text
-rw-rw-r-- 1 student student 45 Nov 11 10:05 app.conf
```

- First character: `-` file, `d` directory, `l` symbolic link.
- Then three groups of `rwx`: **owner**, **group**, **others**. `r` read, `w` write, `x` execute (for a directory, `x` means "may enter / pass through").
- Then the owner (`student`) and group (`student`).

Numbers are a short form: `r=4`, `w=2`, `x=1`, added per group. `640` = owner `rw-`, group `r--`, others `---`.

```bash
chmod 640 app.conf
ls -l app.conf
chmod o+r app.conf
ls -l app.conf
chmod u+x,g-r app.conf
ls -l app.conf
chmod 644 app.conf
ls -l app.conf
```

Common values in these labs:

| Mode | Used for |
| --- | --- |
| `644` | Normal readable files (web pages, configs) |
| `640` | Files only the owner and one group may read (password files) |
| `755` | Folders and scripts everyone may enter or run |
| `750` | Folders only the owner and one group may enter (`/opt/tomcat`) |

Ownership changes need `sudo`:

```bash
sudo chown root:root app.conf
ls -l app.conf
echo "extra=1" >> app.conf
sudo chown "$USER:$USER" app.conf
ls -l app.conf
```

- The `echo` fails with `Permission denied`: the file now belongs to root and others may only read it. Changing it back to you fixes it.

A file is only readable if **every folder on the path** can be entered. `namei -l` shows each step:

```bash
namei -l ~/lab/practice/conf/app.conf
sudo -u www-data cat ~/lab/practice/conf/app.conf
```

- Ubuntu 24.04 home folders are `drwxr-x---` (750). The `www-data` user (the web server user) is "others" there, so it cannot pass through your home folder and gets `Permission denied`.
- This is why web content goes in `/var/www`, not in a home folder.

`umask` decides the permissions of new files:

```bash
umask
touch new-file.txt
mkdir new-dir
ls -ld new-file.txt new-dir
```

- With `umask 0002` (usual for desktop users) new files are `664` and folders `775`. With `0022` (usual for servers and services) they are `644` and `755`.
- The Tomcat and Kong unit files in later labs set `UMask=0027`, so their new log files are not readable by others.

## 7. Users, groups and sudo

```bash
id
groups
getent passwd root
getent passwd www-data
getent group sudo
sudo -l
```

- `/etc/passwd` lines are `name:x:uid:gid:comment:home:shell`. Service accounts such as `www-data` use a shell like `/usr/sbin/nologin`: they run software, nobody logs in as them.
- Members of the `sudo` group may run commands as root. `sudo -l` lists what you may do.
- `sudo -u <user> <command>` runs one command as another user. You use it in later labs to check "can the service user read this file?".

## 8. Processes

```bash
ps -ef | head -n 15
ps -eo pid,ppid,user,%cpu,%mem,cmd --sort=-%cpu | head -n 10
pgrep -a systemd
top -b -n 1 | head -n 15
```

- Every running program is a **process** with a PID (process ID) and a PPID (parent's PID).
- `ps -eo` lets you choose the columns; `--sort=-%cpu` puts the busiest first.
- `pgrep -a <name>` finds processes by name.
- `top -b -n 1` prints one snapshot (batch mode), which you can save as evidence. Plain `top` is interactive: `P` sorts by CPU, `M` by memory, `q` quits.

Start and stop a harmless background process:

```bash
sleep 600 &
jobs
pgrep -a sleep
kill -TERM "$(pgrep -n sleep)"
jobs
```

- `&` runs a command in the background; `jobs` lists background jobs of this terminal.
- `kill -TERM` (signal 15, the default) asks a process to stop cleanly. It can tidy up and close files.
- `kill -KILL` (signal 9) ends it immediately with no clean-up. Use it only when `-TERM` did not work. Services are normally stopped with `systemctl stop`, which sends `TERM` first.

`nice` starts a process with lower priority so it disturbs others less:

```bash
nice -n 10 sleep 30 &
ps -o pid,ni,cmd -p "$(pgrep -n sleep)"
kill "$(pgrep -n sleep)"
```

Expected: the `NI` column shows `10`.

## 9. Memory, disk and load

```bash
free -h
df -h
df -h /var/log
du -sh ~/lab
sudo du -sh /var/log
uptime
nproc
```

- `free -h`: look at **available**, not **free**. Linux uses spare memory as cache; `available` is what new programs can really get.
- `df -h` shows space per file system. If the file system holding `/var/log` reaches 100 %, services cannot write logs and may fail.
- `du -sh` shows how much one folder uses. Use it to find what is filling a disk.
- `uptime` prints three **load averages** (last 1, 5 and 15 minutes). Compare them with `nproc` (number of CPU cores): a load near or above the core count means the machine is busy.

## 10. Services with systemd

Each long-running server program is a **service** (a systemd unit). Practise on services that already exist on Ubuntu:

```bash
systemctl status cron --no-pager
systemctl is-active cron
systemctl is-enabled cron
systemctl list-units --type=service --state=running --no-pager
systemctl list-units --failed --no-pager
```

- `is-active`: running now? `is-enabled`: will it start at boot? They are separate questions.
- `--failed` lists units that crashed or failed to start. Run it first when something "stopped working".

Read a service's log with `journalctl`:

```bash
sudo journalctl -u cron -n 20 --no-pager
sudo journalctl -u cron --since '1 hour ago' --no-pager
sudo journalctl -p err -b --no-pager | tail -n 20
```

- `-u` selects the unit, `-n` the number of lines, `--since` a time window, `-p err` errors only, `-b` since the last boot.
- `sudo journalctl -u cron -f` follows new lines live; stop it with Ctrl+C.
- The service commands you will use later: `sudo systemctl start|stop|restart|reload <name>`. `reload` re-reads configuration without dropping connections, if the service supports it.

## 11. Ports and networking

```bash
ip -br a
ip route
sudo ss -lntp
cat /etc/hosts
getent hosts localhost
getent ahosts ubuntu.com
```

- `ip -br a` lists network interfaces and addresses briefly. `lo` with `127.0.0.1` is loopback: "this laptop".
- `ip route` shows the default gateway (the `default via` line).
- `ss -lntp`: **l**istening, **n**umeric, **t**CP, with **p**rocess. Each line is a port some program is waiting on. `0.0.0.0:80` means all addresses; `127.0.0.1:8080` means local only.
- `getent hosts <name>` resolves a name the same way most programs do: `/etc/hosts` first, then DNS. You do not need `dig`.

Check reachability and HTTP answers:

```bash
ping -c 3 127.0.0.1
ping -c 3 ubuntu.com
curl -I https://ubuntu.com/
curl -s -o ~/lab/practice/ubuntu-home.html -w 'status=%{http_code} time=%{time_total}s\n' https://ubuntu.com/
wget -O ~/lab/practice/ubuntu-home-wget.html https://ubuntu.com/
ls -lh ~/lab/practice/*.html
```

- `ping` proves the network path and name resolution, not that a web server works. Some networks block ping; then try curl.
- `curl -I` shows only response headers; the first line has the status code.
- `curl -o <file>` saves the body; `-w` prints values such as the status code and total time.
- `curl -v` prints every step: name lookup, TCP connect, request and response headers. Use it when a request fails and you do not know where.

Run your own small web server on a test port and check it:

```bash
cd ~/lab/practice
python3 -m http.server 8099 --bind 127.0.0.1 &
sleep 1
sudo ss -lntp 'sport = :8099'
curl -I http://127.0.0.1:8099/notes.txt
curl -v http://127.0.0.1:8099/notes.txt
nc -zv 127.0.0.1 8099
nc -zv 127.0.0.1 8098
kill %1
```

- `nc -zv` tests only whether a TCP port accepts connections. `succeeded` means something listens; `Connection refused` means nothing listens on that port.
- `kill %1` stops background job 1 of this terminal.

## 12. Search and summarise logs

Generate a sample access log in the same "combined" format Apache and Nginx use later:

```bash
cd ~/lab/practice/logs
for i in $(seq 1 200); do
  ip="10.0.0.$(( i % 7 + 1 ))"
  status=200; path=/index.html
  if [ $(( i % 10 )) -eq 0 ]; then status=404; path=/missing.html; fi
  if [ $(( i % 25 )) -eq 0 ]; then status=500; path=/payment/fail; fi
  if [ $(( i % 33 )) -eq 0 ]; then status=401; path=/admin/; fi
  printf '%s - - [11/Nov/2026:10:%02d:%02d +0530] "GET %s HTTP/1.1" %s %s "-" "curl/8.5.0"\n' \
    "$ip" $(( i / 60 )) $(( i % 60 )) "$path" "$status" $(( 100 + i ))
done > access.log
wc -l access.log
head -n 3 access.log
```

Sample line:

```text
10.0.0.2 - - [11/Nov/2026:10:00:01 +0530] "GET /index.html HTTP/1.1" 200 101 "-" "curl/8.5.0"
```

Search with grep:

```bash
grep -c '" 404 ' access.log
grep -n '" 500 ' access.log
grep -i 'ADMIN' access.log
grep -v '" 200 ' access.log | wc -l
grep -E '" (401|500) ' access.log | tail -n 3
```

- `-c` counts matching lines, `-n` adds line numbers, `-i` ignores upper/lower case, `-v` shows lines that do **not** match, `-E` allows `(a|b)` patterns.
- Searching for `" 404 ` (quote, space, code, space) matches the status field, not a size or time that happens to contain `404`.

Count with awk, sort and uniq. awk splits each line on spaces; in this format field 1 is the client address, field 7 the path and field 9 the status:

```bash
awk '{print $9}' access.log | sort | uniq -c | sort -rn
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -n 3
awk '$9 >= 500 {print $4, $7, $9}' access.log
awk '$9 == 404 {print $7}' access.log | sort | uniq -c
```

Expected status counts: `170` × 200, `16` × 404, `8` × 500, `6` × 401.

- `sort | uniq -c | sort -rn` is the most-used log pipeline: group equal lines, count them, biggest first.

Follow a log while it grows. In terminal A:

```bash
tail -f ~/lab/practice/logs/access.log
```

In terminal B:

```bash
echo '10.0.0.9 - - [11/Nov/2026:10:05:00 +0530] "GET /live-test HTTP/1.1" 404 120 "-" "curl/8.5.0"' >> ~/lab/practice/logs/access.log
```

The new line appears in terminal A at once. Stop `tail -f` with Ctrl+C.

Read a long file page by page:

```bash
less ~/lab/practice/logs/access.log
```

- Space = next page, `b` = back, `/500` + Enter = search, `n` = next match, `G` = end, `q` = quit.

## 13. Archives and checksums

Back up the practice folder, list the archive, and restore it to a different place:

```bash
cd ~/lab
tar czf ~/lab/backups/practice-$(date +%F).tar.gz -C ~/lab practice
ls -lh ~/lab/backups/
tar tzf ~/lab/backups/practice-$(date +%F).tar.gz | head
mkdir -p ~/lab/restore
tar xzf ~/lab/backups/practice-$(date +%F).tar.gz -C ~/lab/restore
diff -r ~/lab/practice ~/lab/restore/practice && echo "restore matches"
```

- `c` create, `t` list, `x` extract, `z` gzip, `f` the archive file name. `-C` changes folder first, so the archive stores the path `practice/...` instead of your full home path.
- Always **list** (`tzf`) an archive before extracting it, so you know where its files will land.

Zip files. A Java WAR file is a zip file:

```bash
sudo apt install -y zip
cd ~/lab
zip -r ~/lab/backups/practice.zip practice
unzip -l ~/lab/backups/practice.zip | tail -n 5
unzip -l ~/ltm/middleware-labs/project-files/apps/payment.war
```

Checksums prove a file was not changed or damaged:

```bash
cd ~/lab/backups
sha256sum practice-*.tar.gz practice.zip > SHA256SUMS
cat SHA256SUMS
sha256sum -c SHA256SUMS
echo "tamper" >> practice.zip
sha256sum -c SHA256SUMS
zip -r ~/lab/backups/practice.zip ~/lab/practice > /dev/null
```

- The first check prints `OK` for every file. After the `echo`, the zip reports `FAILED` — any change, even one byte, changes the checksum. The project repository uses the same check (`sha256sum -c SHA256SUMS`) in student start.
- The last line rebuilds the zip; its checksum is now different, so make a new `SHA256SUMS` if you keep it.

## 14. Break it, find it

Each scenario creates a small, deliberate fault under `~/lab`, shows you how to find it with the tools above, and then removes it. Do them in order.

### Scenario A — "No space left on device"

Create a small 20 MB test disk inside `~/lab`, then overfill it:

```bash
mkdir -p ~/lab/smalldisk
sudo mount -t tmpfs -o size=20M tmpfs ~/lab/smalldisk
sudo chown "$USER:$USER" ~/lab/smalldisk
df -h ~/lab/smalldisk
fallocate -l 15M ~/lab/smalldisk/old-app.log
fallocate -l 10M ~/lab/smalldisk/new-app.log
echo "one more log line" >> ~/lab/smalldisk/new-app.log
```

Sample line:

```text
fallocate: fallocate failed: No space left on device
```

Find what is using the space:

```bash
df -h ~/lab/smalldisk
du -sh ~/lab/smalldisk/* | sort -h
```

- `df` tells you **which file system** is full; `du` tells you **which files** fill it. On a real server you would run `sudo du -sh /var/log/* | sort -h`.
- Fix: remove or archive the oldest log, never a file a running service is still writing to without checking first.

Recover:

```bash
rm ~/lab/smalldisk/old-app.log
df -h ~/lab/smalldisk
sudo umount ~/lab/smalldisk
rmdir ~/lab/smalldisk
```

### Scenario B — a runaway process

```bash
yes > /dev/null &
top -b -n 1 | head -n 12
ps -eo pid,user,%cpu,cmd --sort=-%cpu | head -n 5
```

- `yes` uses a whole CPU core. It appears at the top of both lists with close to 100 % CPU.
- `uptime` load rises over the next minute.

Stop it and verify:

```bash
kill -TERM "$(pgrep -x yes)"
pgrep -a yes || echo "no yes process left"
```

### Scenario C — port already in use

```bash
cd ~/lab/practice
python3 -m http.server 8099 --bind 127.0.0.1 &
sleep 1
python3 -m http.server 8099 --bind 127.0.0.1
```

Sample line:

```text
OSError: [Errno 98] Address already in use
```

- The second server cannot start because the first already listens on 8099. The same thing happens when Apache and Nginx both want port 80.
- Find the owner of the port:

```bash
sudo ss -lntp 'sport = :8099'
```

Sample line:

```text
LISTEN 0      5          127.0.0.1:8099      0.0.0.0:*    users:(("python3",pid=4321,fd=3))
```

Recover by stopping the process that holds the port:

```bash
kill %1
sudo ss -lntp 'sport = :8099'
```

Expected: the second `ss` prints only the header line.

### Scenario D — permission denied

```bash
cd ~/lab/practice/conf
chmod 000 app.conf
cat app.conf
ls -l app.conf
chmod 755 ~/lab/practice/conf
chmod 644 app.conf
chmod 600 ~/lab/practice/conf
ls ~/lab/practice/conf
sudo -u www-data ls /home
namei -l ~/lab/practice/conf/app.conf
```

- `chmod 000` removes every permission, so even you get `cat: app.conf: Permission denied`.
- `namei -l` shows which folder on the path is missing the `x` bit. Here `conf` is `drw-------`: you can see the names inside but cannot open the files.

Recover:

```bash
chmod 755 ~/lab/practice/conf
chmod 644 ~/lab/practice/conf/app.conf
cat ~/lab/practice/conf/app.conf
```

### Scenario E — "Could not resolve host"

```bash
curl -I http://lab0.example.test/
getent hosts lab0.example.test || echo "name not found"
```

Sample line:

```text
curl: (6) Could not resolve host: lab0.example.test
```

- The program never reached any server: the **name** could not be turned into an address. This is different from `Connection refused` (address found, nothing listening) and from an HTTP error code (a server answered).
- In Lab 1 you fix this kind of problem for `portal.example.test` by adding one line to `/etc/hosts`.

## 15. Self-check

Answer from memory, then check with a command.

1. Which command shows the permissions of a folder itself rather than its contents?
2. A file is `-rw-r-----  root www-data`. Can `www-data` read it? Can it write it? Can your own account read it?
3. What is the difference between `kill -TERM` and `kill -KILL`?
4. `free -h` shows `free 200Mi` and `available 2.1Gi`. Is the laptop out of memory?
5. Which command shows the program listening on port 8099?
6. Write a pipeline that prints the top three client addresses in `access.log`.
7. How do you prove a backup archive was not changed since you made it?
8. `curl` says `Connection refused` on port 8080. Is it a name problem, a network problem or "nothing listening"?

Answers:

1. `ls -ld <folder>`.
2. Yes (group `r`); no (no group `w`); no — you are "others", with no permissions (unless you use `sudo`).
3. `TERM` asks the process to finish cleanly; `KILL` ends it immediately without clean-up. Try `TERM` first.
4. No. `available` is what programs can use; much of the rest is cache Linux gives back when needed.
5. `sudo ss -lntp 'sport = :8099'`.
6. `awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -n 3`.
7. Record `sha256sum` when you make it, later run `sha256sum -c`.
8. Nothing listening on that address and port: the name resolved and the laptop answered, but no program accepted the connection.

## 16. Clean up

```bash
pgrep -a 'yes|http.server' || echo "no practice processes left"
ls ~/lab
```

Keep `~/lab/practice`; Lab 6 reuses the same log commands. Continue to [Lab 1 — Apache](01-apache.md).
