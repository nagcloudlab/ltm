# 06 · Processes: see, stop, background

**Time:** 60 min

**Part A · Basics** on your own lab VM. **Part B · In depth** on the PayBank lab server (`~/lab/srv`, built by `00-setup.md`).

**You will learn in Part B:** background jobs `&` `jobs` `fg` `bg` `nohup`, `ps aux`, top keys, `kill` signals, `pkill`, `2>`, `2>&1`, `tee`, `$( )`

---

# Part A · Basics

## 06.1 · Processes


```bash
ps -ef | grep sshd
pgrep -a sshd
```

| Column | Meaning |
|---|---|
| UID | user running it |
| PID | process number |
| PPID | parent's PID |
| CMD | the command |

- **The pipe `|`** sends the output of the command on its left into the command on its right. Here `ps -ef` lists every process and `grep sshd` keeps only lines containing sshd. From now on we use pipes often.
- The last `grep` line is the grep itself: ignore it. `pgrep` avoids it.

### top

```bash
top
```

Press `P` (sort by CPU), `M` (sort by memory), `q` (quit). Look at:

- `load average:` how busy the machine was over 1, 5, 15 minutes
- `%Cpu(s): ... id` idle percent (high = spare capacity)
- the table: busiest process first


---

# Part B · In depth: the PayBank lab server

```bash
cd ~/lab/srv
```

## 06.2 · Run in the background: `&`

```bash
sleep 120 &
echo "my terminal is free"
```

`[1]` = job number in **this** shell. `4512` = PID for the whole system.

## 06.3 · See your jobs

```bash
sleep 200 &
jobs -l
```

`+` = current job (what `fg` uses), `-` = previous.

## 06.4 · Pause, continue, bring back

```bash
tail -f /var/log/syslog
# then press Ctrl+Z
jobs                # find its job number, e.g. [1]+ Stopped
bg                  # continue the current job in the background
fg                  # bring it back to the front
# then press Ctrl+C                # stop it for good
```

```
running in front ──Ctrl+Z──► stopped ──bg──► running in background
       ▲                                           │
       └───────────────────fg──────────────────────┘
```

| Command | Does |
|---|---|
| `cmd &` | start in background |
| `Ctrl+Z` | pause the front job |
| `bg %n` | resume job n in background |
| `fg %n` | bring job n to front |
| `kill %n` | stop job n |
| `jobs -l` | list with PIDs |

> A background job still prints to your screen. Redirect it: `cmd > out.log 2>&1 &`.

## 06.5 · Survive logout: `nohup`

Jobs started with `&` normally die when you close the ssh session. `nohup` keeps them running:

```bash
nohup bash -c 'for i in $(seq 1 30); do date; sleep 10; done' > ~/clock.log 2>&1 &
exit
```

Log in again:

```bash
pgrep -af "seq 1 30"
tail -n 2 ~/clock.log
```

```
nohup  command   > ~/clock.log   2>&1        &
│                 │               │           └ background
│                 │               └ errors go to the same file
│                 └ normal output into this file
└ ignore the "hang up" signal sent at logout
```

> For anything that must run **always** (an app server, a gateway), use a **systemd service**, not nohup: systemd restarts it after a crash and a reboot (Topic 08 services, Module 5 Tomcat).

## 06.6 · Start the runaway (the trainer's "bug")

```bash
nohup scripts/rebuild_index.sh > /dev/null 2>&1 &
```

(`nohup … &` from the background-jobs sections above: it starts the script in the background and keeps it running.)

## 06.7 · Who is eating the CPU? (`top`)

```bash
top
```

### Reading the header

| Field | Meaning | Here |
|---|---|---|
| `load average: 0.98, 0.52, 0.21` | busy-ness over 1, 5, 15 min. Compare with `nproc` | rising fast |
| `us` | CPU used by programs | 50% (1 of 2 cores) |
| `id` | idle | 49.6% |
| `wa` | waiting for disk | 0: not a disk problem |

### Columns

| Column | Meaning |
|---|---|
| `PID` | process ID |
| `S` | state: `R` running, `S` sleeping, `D` waiting on disk, `Z` zombie |
| `%CPU` | 100 = one full core |
| `RES` | real memory used |
| `TIME+` | total CPU time used so far |

| Key in top | Does |
|---|---|
| `P` / `M` | sort by CPU / memory |
| `1` | show each core separately |
| `c` | show the full command line |
| `k` | kill a PID (asks which) |
| `q` | quit |

## 06.8 · Snapshot with ps

```bash
ps aux --sort=-%cpu | head -n 4
pgrep -af rebuild
```

| | `ps aux` | `ps -ef` |
|---|---|---|
| style | BSD | System V |
| shows | %CPU, %MEM, STAT | PPID (the parent) |
| use when | "who is heavy?" | "who started it?" |

| | `top` | `ps` |
|---|---|---|
| live, refreshing | yes | no: one snapshot |
| good for scripts and reports | no | yes |

## 06.9 · Save evidence BEFORE you kill (redirection)

Once you kill it, the evidence is gone. Write it to a file first.

```bash
mkdir -p ~/incident
date                                 > ~/incident/report.txt
echo "== top CPU before kill =="    >> ~/incident/report.txt
ps aux --sort=-%cpu | head -n 5     >> ~/incident/report.txt
cat ~/incident/report.txt
```

| Symbol | Does |
|---|---|
| `>` | write to file, **replacing** what was there |
| `>>` | **append** to the end |
| `2>` | write **errors** (stderr) to a file |
| `2>&1` | send errors to the same place as normal output |
| `\| tee file` | show on screen **and** write to the file |
| `\| tee -a file` | same, appending |

```bash
ls /nonexistent 2> ~/incident/errors.txt      # error goes to the file, not the screen
cat ~/incident/errors.txt
uptime | tee -a ~/incident/report.txt         # see it and save it
```

## 06.10 · Stop it: polite first, force last

```bash
PID=$(pgrep -f rebuild_index)   # store the PID in a name
echo $PID
kill $PID                 # sends SIGTERM (15): "please finish and exit"
pgrep -af rebuild         # still there?
```

Our script ignores nothing, so it stops. A real app might take a few seconds to close files and connections. Wait, check again, and only then:

```bash
kill -9 $PID              # SIGKILL: the kernel ends it immediately
```

| Signal | Number | Means | Use |
|---|---|---|---|
| `SIGTERM` | 15 (default) | please exit cleanly | **always first** |
| `SIGINT` | 2 | same as Ctrl+C | interactive programs |
| `SIGHUP` | 1 | "reload your config" for many daemons | e.g. `kill -HUP` |
| `SIGKILL` | 9 | stop **now**, no cleanup | last resort |
| `0` | 0 | send nothing, just check it exists | `kill -0 PID && echo alive` |

> **Why not `-9` first?** The app gets no chance to finish writing files or release locks. **That is exactly how `/run/payment.lock` was left behind** in our incident: the JVM died without cleaning up.

### By name instead of PID

```bash
pkill -f rebuild_index    # careful: -f matches anywhere in the command line
```

> Run `pgrep -af <name>` first to see exactly what `pkill` would hit.

### Verify and record

```bash
pgrep -af rebuild || echo "rebuild_index stopped"
echo "== $(date +%T) killed PID $PID (rebuild_index.sh, 100% CPU) with SIGTERM ==" >> ~/incident/report.txt
uptime >> ~/incident/report.txt
```

`$(date +%T)` runs `date` and puts its output (the time) into the line.

## 06.11 · Parent and child

```bash
sleep 300 &
ps -o pid,ppid,cmd -p $!          # $! = PID of the last background job
ps -o pid,cmd -p $$               # $$ = PID of your own shell: the parent
kill $!                    # stop that sleep
```

Every process has a parent. Services' parent is `systemd` (PID 1). Apache's workers' parent is the Apache master (Module 3).

---

## Exercises

1. Find the sshd listener with `ps -ef | grep sshd` (the line ending `[listener]`). What is its PPID? Which process is PID 1?
2. Start `sleep 500`, pause it with Ctrl+Z, list it, resume it in the background, then kill it by job number.
3. Start two copies of `rebuild_index.sh`. Show both PIDs with one command.
4. Kill only the **newer** one (`pgrep -n` = newest).
5. Using `kill -0`, check whether the older one is alive.
6. Append the 5 processes using most **memory** to your report.
7. Stop the remaining copy and confirm in one line.

## Answers

1. PPID 1. PID 1 is `systemd`, which starts and watches all services.
2. `sleep 500` → `Ctrl+Z` → `jobs` → `bg %1` → `kill %1`.
3. `nohup scripts/rebuild_index.sh >/dev/null 2>&1 &` twice; `pgrep -af rebuild`.
4. `kill $(pgrep -nf rebuild_index)`.
5. `kill -0 $(pgrep -of rebuild_index) && echo alive` (`-o` = oldest).
6. `ps aux --sort=-%mem | head -n 6 >> ~/incident/report.txt`.
7. `pkill -f rebuild_index; pgrep -f rebuild_index || echo stopped`.
