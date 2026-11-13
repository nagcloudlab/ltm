# 07 · CPU, memory, disk

**Time:** 55 min

**Part A · Basics** on your own lab VM. **Part B · In depth** on the PayBank lab server (`~/lab/srv`, built by `00-setup.md`).

**You will learn in Part B:** `df -i` (inodes), `du --max-depth`, compress with `gzip`/`zcat`, the deleted-but-still-open trap (`lsof`, `truncate`), logrotate

---

# Part A · Basics

## 07.1 · Server health: CPU, memory, disk


### CPU

```bash
nproc
```

In `top`, 100% = one full core. On a 2-core server, 180% means about 90% of the whole machine.

### Memory: watch `available`, not `free`

```bash
free -h
```

| Column | Restaurant picture | Meaning |
|---|---|---|
| used | tables with diners | programs are using it |
| buff/cache | tables with snacks, cleared in a second | borrowed to be faster |
| free | the empty table | doing nothing at all |
| **available** | empty + snack tables | **what a new program can get** |

Rule: worry only when `available` gets close to zero.

### Disk: which disk, then which folder

```bash
df -h
```

Read a row as a sentence: *"/ is a 29G disk, 9.8G used, 19G left, 35% full."*

```bash
sudo du -sh /var/log/* | sort -h | tail -n 5
```

| Option | Meaning |
|---|---|
| `du -s` | one total per folder |
| `du -h` / `sort -h` | human sizes, sorted |
| `tail -n 5` | keep the 5 biggest |

### Write down your baseline

| Item | Your value |
|---|---|
| CPU cores (`nproc`) | |
| available memory | |
| `/` disk Use% | |
| biggest folder in /var/log | |


## 07.2 · Scenario: the disk is 95% full


You get an alert: *"lab-vm-01: / at 95%"*. Follow five calm steps:

| Step | Command | You find |
|---|---|---|
| 1 Which disk? | `df -h` | `/` is 95% |
| 2 Which folder? | `sudo du -sh /var/* \| sort -h` | `/var/log` is biggest |
| 3 Which file? | `sudo find /var/log -size +100M` | one huge old log |
| 4 Clean safely | compress or move it; **ask before deleting** | space is back |
| 5 Stop it again | check log rotation; alert at 80% | warning next time |

Run steps 1–3 on your VM (your disk is not really full; read the numbers):

```bash
df -h /
sudo du -sh /var/* | sort -h | tail -n 3
sudo find /var/log -size +10M
```

> **Trap:** you deleted a big log but `df` did not change? A running program still holds the file open. The space comes back when that program restarts.

---

# Part B · In depth: the PayBank lab server

```bash
cd ~/lab/srv
```

## 07.3 · Load average, read properly

```bash
uptime
nproc
```

| Load ÷ cores | Means |
|---|---|
| below 0.7 | relaxed |
| about 1.0 | fully busy |
| above 1.0 | work is **waiting** in a queue |

`2.40 ÷ 2 = 1.2` and the 1-minute number is the highest: load is **rising right now**. Load counts processes running **or** waiting for disk, so high load with low CPU% usually means a slow disk.

## 07.4 · vmstat: CPU, memory, disk in one line per second

```bash
vmstat 2 5
```

| Column | Watch for |
|---|---|
| `r` | processes waiting for CPU: more than cores = CPU bottleneck |
| `b` | processes blocked on disk |
| `si` / `so` | swap in / out: **anything above 0 for long = memory pressure** |
| `us` / `sy` / `id` / `wa` | CPU: programs / kernel / idle / waiting for disk |

`vmstat 2 5` = every 2 seconds, 5 times. Ignore the first line (averages since boot).

## 07.5 · Who uses the memory?

```bash
ps aux --sort=-%mem | head -n 5
top                # then press M
```

`RSS` (ps) and `RES` (top) are the real memory a process holds. A Java app server shows a large RSS by design: its heap is reserved up front (Module 5).

## 07.6 · Swap

```bash
swapon --show
free -h | grep Swap
```

Swap is disk used as emergency memory, 100× slower. A little used swap is fine; swap **growing** while `available` shrinks means the server is about to slow down badly.

## 07.7 · When memory runs out: the OOM killer

```bash
sudo dmesg -T | grep -i -E "out of memory|killed process"
sudo journalctl -k --since today | grep -i oom
```

When memory and swap are both exhausted, the kernel's **OOM killer** stops a process, usually the biggest: often the Java app server. If an app "disappeared" with nothing in its own log, check `dmesg` first.

> This is different from the PayBank log’s `Java heap space` error: there **Java’s own** limit (`-Xmx`, 512m) was hit while the machine still had memory. Both look like "the app died"; the logs tell them apart.

## 07.8 · /proc: live numbers straight from the kernel

```bash
head -n 3 /proc/meminfo
cat /proc/loadavg
grep -c processor /proc/cpuinfo
```

`free`, `uptime` and `nproc` read these files. Scripts often read them directly.

## 07.9 · Which disk? (`df`)

```bash
df -h
df -h ~/lab
```

Your lab VM is not really full; the numbers in the steps below come from `~/lab/srv`. The **method** is what matters.

### The other "disk full": inodes

```bash
df -i /
```

Every file uses one inode. Millions of tiny files (session files, mail queues) can use **100% of inodes** while `df -h` still shows free space; then "No space left on device" appears anyway. Always check both.

## 07.10 · Which folder? (`du`)

```bash
du -sh ~/lab/srv/*/ | sort -h
du -h --max-depth=2 opt | sort -h | tail -n 3
```

| | `df` | `du` |
|---|---|---|
| answers | which **disk** is full | which **folder** is big |
| speed | instant | reads every file: slow on big trees |
| run first | yes | after df |

## 07.11 · Which files?

```bash
find . -type f -size +10M -exec ls -lh {} \; | sort -k5 -h
```

| File | What it is | Safe action |
|---|---|---|
| `catalina.2026-08-23.log` | yesterday's app log | compress it, keep the `.gz` |
| `heapdump-4123.hprof` | memory dump from the crash | **evidence for developers**: move it off the server, don't delete |
| `access.log.1` | yesterday's Apache log | compress |

## 07.12 · Compress, don't delete

```bash
gzip opt/tomcat/logs/catalina.2026-08-23.log
ls -lh opt/tomcat/logs/
```

Our fake log is all zeros, so it shrinks to almost nothing. Real text logs usually shrink to 5–15% of their size.

Read it without unpacking:

```bash
zcat opt/tomcat/logs/catalina.2026-08-23.log.gz | head -c 100 | wc -c
zgrep -c ERROR var/log/payment/archived/*.gz
```

### Move evidence off the server

```bash
mkdir -p ~/for-developers && mv opt/tomcat/logs/heapdump-4123.hprof ~/for-developers/
```

In real life: `scp` it to a shared server (Topic 13), then remove it here.

```bash
du -sh ~/lab/srv
```

## 07.13 · The trap: deleted, but the space did not come back

A program writes to a log. You delete the log. `df` does not change. Why? The program still has the file **open**; Linux frees the space only when the last program closes it.

Try it:

```bash
fallocate -l 200M ~/lab/srv/var/log/payment/big.log   # a 200 MB "log"
tail -f ~/lab/srv/var/log/payment/big.log > /dev/null &  # a program keeps it open
df -h ~ | tail -1                    # note Used
rm ~/lab/srv/var/log/payment/big.log
df -h ~ | tail -1                    # Used did NOT drop
sudo lsof +L1 | grep big.log         # deleted files that are still open
kill %1                              # the program closes it
df -h ~ | tail -1                    # now the space is back
```

| Fix | When |
|---|---|
| restart / reload the program | normal case |
| `truncate -s 0 file` **instead of** `rm` | a log you must empty while the app keeps running |

> **Better habit:** to empty a live log, `truncate -s 0 app.log` (or `> app.log`). The file stays, the program keeps writing, the space is freed at once.

## 07.14 · Stop it coming back: log rotation

Ubuntu rotates system logs with **logrotate**:

```bash
cat /etc/logrotate.d/rsyslog
```

| Line | Means |
|---|---|
| `weekly` | rotate once a week |
| `rotate 4` | keep 4 old files |
| `compress` + `delaycompress` | gzip old files, but keep yesterday's uncompressed |
| `postrotate … endscript` | tell the program to reopen its log (avoids the trap in 07.13) |

Apache's own rule (`/etc/logrotate.d/apache2`, after Module 3 installs it) uses `daily` and `rotate 14`.

A log that fills the disk usually belongs to an app **without** a logrotate rule. The fix is a rule, not a nightly `rm`.

---

## Exercises

1. `free` shows 0.2Gi but `available` shows 2.5Gi. Is the server short of memory?
2. Which single file under `~/lab/srv` is the largest right now?
3. Compress `access.log.1` and show the space saved.
4. Find every `.gz` older than 7 days (after `touch -d "10 days ago"` on two of them).
5. Explain in one sentence why `df` and `du` can disagree.
6. Write the logrotate settings you would want for `/var/log/payment/*.log`: weekly, keep 8, compressed.
7. Run `vmstat 1 5` while `rebuild_index.sh` runs (Topic 06). Which columns change?
8. Load average is `0.40 0.35 0.30` on a 2-core server. Busy?
9. Find the 3 processes holding the most memory.
10. An app vanished at 03:12 and its log shows nothing. What do you check?

## Answers

1. No. `available` (2.5Gi) is what programs can get; a small `free` is normal.
2. `find . -type f -exec ls -s {} \; | sort -n | tail -1` (or `du -a . | sort -n | tail -1`).
3. `ls -lh var/log/apache2/access.log.1; gzip var/log/apache2/access.log.1; ls -lh var/log/apache2/`.
4. `find . -name "*.gz" -mtime +7`.
5. `du` counts files it can see; `df` counts used blocks, including deleted files still held open by running programs.
6. ```
   /var/log/payment/*.log {
       weekly
       rotate 8
       compress
       missingok
       notifempty
   }
   ```
7. `r` goes to 1–2 and `us` to about 50 (one core of two), `id` drops.
8. No: 0.40 ÷ 2 = 0.2, relaxed.
9. `ps aux --sort=-%mem | head -n 4`.
10. `sudo dmesg -T | grep -i "killed process"` and `journalctl -k` around 03:12 for the OOM killer.
