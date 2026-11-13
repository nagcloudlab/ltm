# 18 · Advanced: resources under pressure

**Time:** 50 min

**Practise on** your own lab VM. **Needs:** paysim from Topic 17 running.

**You will learn:** CPU and disk statistics with `iostat`, `pidstat` and `sar`; open-file limits and "Too many open files"; a full disk and full inodes on a safe test disk; the OOM killer in action; reading connections with `ss` filters and `lsof -i`.

- Topic 07 showed the basic numbers. This topic **causes** each problem on purpose, safely, so you recognise the message when you meet it at work.
- Everything here happens on small test disks or inside limits. Your real disk and memory are not filled.

---

## 18.1 · The sysstat tools: iostat, pidstat, sar

```bash
sudo apt install -y sysstat
iostat -xz 2 3
pidstat 2 3
sar -u 2 3
```

- Package **sysstat** gives `iostat`, `pidstat`, `sar`, `mpstat`.
- `2 3` = every 2 seconds, 3 times (same idea as `vmstat 2 5`, Topic 07).
- In `iostat`, ignore the first report: it is the average since boot.

| Tool | Answers |
|---|---|
| `iostat -xz` | is a **disk** busy or slow? |
| `pidstat` | **which process** uses CPU right now (only busy ones are listed) |
| `sar -u` | CPU use: `%user`, `%system`, `%iowait`, `%idle` |
| `mpstat -P ALL 2 1` | each CPU core separately |

`iostat -xz` columns to read:

| Column | Watch for |
|---|---|
| `r/s` `w/s` | reads / writes per second |
| `r_await` `w_await` | ms per read / write: above 20 ms on SSD = slow disk |
| `aqu-sz` | requests waiting in the disk queue |
| `%util` | near 100 = the disk is the bottleneck |

See the CPU hog from Topic 06 in `pidstat`:

```bash
nohup ~/lab/srv/scripts/rebuild_index.sh > /dev/null 2>&1 &
pidstat 2 2
kill $!
```

- A `bash` process appears with `%CPU` near 100: that is the script (`pgrep -af rebuild` shows the same PID).
- `sar` can also show the **past** (`sar -u` with no numbers) once data collection has run for a while: "how busy was the server at 03:00?"

## 18.2 · Open files: every connection is a file

- Linux counts open files, sockets (network connections) and pipes as **file descriptors**.
- Each process has a **limit**. A busy app server hitting it fails with `Too many open files`.

```bash
ulimit -n
P=$(systemctl show -p MainPID --value paysim)
echo $P
grep "open files" /proc/$P/limits
sudo ls /proc/$P/fd | wc -l
sudo lsof -p $P | tail -n 3
```

- `ulimit -n` = the limit for **your shell** (usually 1024).
- `/proc/<pid>/limits` = the limit of a **running** process. paysim shows 4096: the `LimitNOFILE` from its drop-in (Topic 17.5).
- `/proc/<pid>/fd` = one entry per open file. Compare the count with the limit.

**Break it** (inside a sub-shell, so your own shell is not changed):

```bash
(ulimit -n 50; python3 -c "fs=[open('/etc/hosts') for _ in range(100)]")
```

Sample line:

```text
OSError: [Errno 24] Too many open files: '/etc/hosts'
```

- `Errno 24` / `EMFILE` / `Too many open files` all mean the same: the process hit its open-file limit.
- **Fix for a service:** `LimitNOFILE=65536` in a drop-in, `daemon-reload`, `restart`. (`ulimit` in your shell does not change a service.)
- Also ask: is the app **leaking** files (count keeps growing)? Then raising the limit only delays the crash.

## 18.3 · Disk full, on a safe 20 MB test disk

```bash
sudo mkdir -p /mnt/small
sudo mount -t tmpfs -o size=20M tmpfs /mnt/small
df -h /mnt/small
```

- `tmpfs` = a disk made of memory. `size=20M` keeps it tiny. It disappears at reboot.
- A new tmpfs is writable by every user (like `/tmp`), so no `chown` is needed.

Fill it:

```bash
dd if=/dev/zero of=/mnt/small/big.log bs=1M count=30
df -h /mnt/small
echo "payment ok" >> /mnt/small/app.log
```

Sample lines:

```text
dd: error writing '/mnt/small/big.log': No space left on device
bash: echo: write error: No space left on device
```

- Apps report the same thing as `No space left on device`, `ENOSPC`, or "could not write log".
- Then follow the 5 steps from Topic 07.2. Free it:

```bash
truncate -s 0 /mnt/small/big.log
df -h /mnt/small
```

## 18.4 · Inodes full: "No space" while space is free

```bash
sudo mkdir -p /mnt/tiny
sudo mount -t tmpfs -o size=50M,nr_inodes=200 tmpfs /mnt/tiny
for i in $(seq 1 300); do touch /mnt/tiny/session$i 2>/dev/null || { echo "failed at file $i"; break; }; done
touch /mnt/tiny/one-more
df -h /mnt/tiny
df -i /mnt/tiny
```

- `nr_inodes=200` = this test disk can hold only 200 inodes, whatever the size. The folder itself uses one, so the loop fails at file 200.
- `df -h` shows **0% used**; `df -i` shows **IUse% 100%**. Same error message as a full disk.
- Real causes: millions of small session, cache or mail-queue files. Find the folder with the most files:

```bash
sudo find /var -xdev -type f | cut -d/ -f2-4 | sort | uniq -c | sort -rn | head -n 5
```

Clean up both test disks:

```bash
sudo umount /mnt/small /mnt/tiny
```

## 18.5 · The OOM killer, inside a 50 MB box

- `systemd-run` starts a command as a temporary service. `-p MemoryMax=50M` gives it only 50 MB.
- The command asks for 200 MB, so the kernel's OOM killer stops it. The rest of the server is not touched.

```bash
sudo systemd-run --unit=memhog -p MemoryMax=50M -p MemorySwapMax=0 python3 -c "x = bytearray(200*1024*1024)"
sleep 2
systemctl status memhog --no-pager
journalctl -u memhog --no-pager
sudo dmesg -T | grep -i "killed process" | tail -n 1
```

Sample lines:

```text
systemd[1]: memhog.service: A process of this unit has been killed by the OOM killer.
systemd[1]: memhog.service: Main process exited, code=killed, status=9/KILL
systemd[1]: memhog.service: Failed with result 'oom-kill'.
kernel: Memory cgroup out of memory: Killed process 93243 (python3) total-vm:219196kB, anon-rss:51012kB …
```

- `Result: oom-kill` in `systemctl status` = the service was killed for memory, not a bug in its own log.
- `Memory cgroup out of memory` = a **limit** (`MemoryMax`) was hit. Plain `Out of memory: Killed process` = the **whole server** ran out.
- `anon-rss:51012kB` = about 50 MB in use when it died: the limit.

```bash
sudo systemctl reset-failed memhog
```

## 18.6 · Connections: ss filters and lsof -i

Make some traffic to paysim, and hold 3 connections open for 60 seconds:

```bash
for i in $(seq 1 20); do curl -s -o /dev/null http://127.0.0.1:8085/health; done
for i in 1 2 3; do sleep 60 | nc 127.0.0.1 8085 & done
ss -tan state established '( sport = :8085 )'
ss -tan state time-wait | wc -l
ss -s
sudo lsof -i :8085
sudo ss -ltnp '( sport = :8085 )'
```

| Command | Shows |
|---|---|
| `ss -tan state established` | open conversations right now |
| `ss -tan state time-wait` | finished conversations, kept for about 60 s: normal after many short requests |
| `'( sport = :8085 )'` | only connections on **our** port 8085 (`dport` = the other side's port) |
| `ss -s` | totals by state: a quick health number |
| `lsof -i :8085` | which process owns each connection |

| State | Means | Many of them = |
|---|---|---|
| `LISTEN` | waiting for clients | |
| `ESTAB` | talking | busy, or clients not closing |
| `TIME-WAIT` | just closed | lots of short connections: usually fine |
| `CLOSE-WAIT` | the other side closed, **our app** did not | an **app bug**: connections leak until "Too many open files" |
| `SYN-SENT` | we are trying to connect | the other side is down or blocked |

---

## Exercises

1. Which package gives `iostat`? Which column says a disk is fully busy?
2. paysim's limit is 4096 open files. Prove it, and count how many it has open now.
3. An app log says `Errno 24`. What does it mean, and where do you fix it for a systemd service?
4. `df -h` shows 40% used but the app says "No space left on device". What is your next command?
5. A service shows `Result: oom-kill`. Was it the whole server out of memory or a limit? How do you tell?
6. 300 connections to your app server are in `CLOSE-WAIT`. Whose problem is it?

## Answers

1. `sysstat`; `%util` near 100.
2. `grep "open files" /proc/$(systemctl show -p MainPID --value paysim)/limits` → 4096; `sudo ls /proc/<pid>/fd | wc -l`.
3. Too many open files: the process hit its limit. `LimitNOFILE=` in a drop-in, then `daemon-reload` and `restart`.
4. `df -i`: the inodes are probably full.
5. `sudo dmesg -T | grep -i "killed process"`: `Memory cgroup out of memory` = a limit; `Out of memory` alone = the whole server.
6. The app's (developers): it does not close connections the other side already closed.
