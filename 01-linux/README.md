# 01 · Linux for Middleware Admins · Topic labs

A detailed hands-on handout: **one topic per file**, in teaching order. Read the explanation, type the commands, do the exercises.

Every topic file has two parts:

| Part | What | Where you practise |
|---|---|---|
| **Part A · Basics** | the essential commands, step by step | your own Ubuntu 24.04 lab VM |
| **Part B · In depth** | deeper commands and real admin situations | the PayBank lab server `~/lab/srv` (built by `00-setup.md`) |

Do **Part A of all topics first**, in order. Then do Part B topic by topic.

Topics 17–21 are **advanced**: do them after Topic 16, in order (each one uses what the one before built).

---

## Topics

| # | File | Topic | Part A | Part B |
|---|---|---|---|---|
| 00 | [00-setup.md](00-setup.md) | build the PayBank lab server | — | 5 min |
| 01 | [01-shell-and-commands.md](01-shell-and-commands.md) | log in, shell, command parts, prompt, keys, Red Hat | 15 min | 5 min |
| 02 | [02-navigation.md](02-navigation.md) | tree, folders, `pwd` `cd` paths, `ls`, wildcards, links | 15 min | 20 min |
| 03 | [03-files.md](03-files.md) | create, copy, delete, read, `find`, `diff` | 15 min | 45 min |
| 04 | [04-vi-editor.md](04-vi-editor.md) | modes, keys, back up first, search/replace | 15 min | 15 min |
| 05 | [05-users-and-permissions.md](05-users-and-permissions.md) | root, `sudo`, permissions, groups, `www-data` | 15 min | 20 min |
| 06 | [06-processes.md](06-processes.md) | `ps` `top`, background jobs, `kill`, evidence | 10 min | 45 min |
| 07 | [07-cpu-memory-disk.md](07-cpu-memory-disk.md) | load, memory, swap, OOM, `df` `du`, cleanup | 25 min | 45 min |
| 08 | [08-services-and-scheduling.md](08-services-and-scheduling.md) | `systemctl`, cron, timers, `at` | 15 min | 30 min |
| 09 | [09-logs-and-grep.md](09-logs-and-grep.md) | logs, `tail -f`, `journalctl`, grep deep, `cut` `awk` `sort` | 30 min | 60 min |
| 10 | [10-network.md](10-network.md) | IP, ports, `ss`, DNS, `ping` `nc` `curl`, routes | 15 min | 25 min |
| 11 | [11-software-and-archives.md](11-software-and-archives.md) | `apt`, `dpkg`, holds, `tar` | 10 min | 15 min |
| 12 | [12-environment.md](12-environment.md) | variables, PATH, `JAVA_HOME`, `.bashrc`, aliases | — | 30 min |
| 13 | [13-remote-access.md](13-remote-access.md) | ssh keys, `scp`, `rsync` (needs a partner) | — | 30 min |
| 14 | [14-shell-scripting.md](14-shell-scripting.md) | scripts up to a full morning health check | — | 50 min |
| 15 | [15-lab1-server-checkup.md](15-lab1-server-checkup.md) | **Lab 1**: server check-up | 20 min | — |
| 16 | [16-incident-drill.md](16-incident-drill.md) | **Capstone:** "Payment is down", with answer key | — | 45 min |
| 17 | [17-advanced-systemd.md](17-advanced-systemd.md) | **Advanced:** your own service, restart policies, drop-ins, journalctl filters, timers | — | 45 min |
| 18 | [18-advanced-resources.md](18-advanced-resources.md) | **Advanced:** iostat/pidstat/sar, open-file limits, disk and inodes full, OOM killer, `ss` states | — | 50 min |
| 19 | [19-advanced-network-dns-time.md](19-advanced-network-dns-time.md) | **Advanced:** `/etc/hosts` vs `dig`, `curl --resolve` and timings, clock and time zones, certificate expiry | — | 35 min |
| 20 | [20-reading-logs.md](20-reading-logs.md) | **Reading logs:** line anatomy for syslog, journal, auth.log, dmesg, Apache, app; one timeline from three logs; drills | — | 45 min |
| 21 | [21-troubleshooting-scenarios.md](21-troubleshooting-scenarios.md) | **Troubleshooting scenarios:** 9 break-read-fix cases and a mixed drill, in pairs | — | 75 min |
| 99 | [99-cheatsheet.md](99-cheatsheet.md) | one-page reference | | |
| — | [_trainer-notes.md](_trainer-notes.md) | pre-checks, timing, common snags | | |

---

## How to use the files

- **Command blocks contain only commands.** Copy a block and paste it into the terminal, or type it line by line (typing is better for learning).
- Text after `#` on a command line is a comment; bash ignores it, so it is safe to paste.
- `# then press Ctrl+C` (or `Ctrl+Z`) inside a block means: press those keys at that point.
- Your output will differ from your neighbour's (PIDs, sizes, dates, IPs). Compare the **shape**, and read the explanation tables under each block.
- Plain blocks without commands are diagrams, config lines to type into a file, or log lines to read.
- Each topic ends with **Exercises** and **Answers**. Try first, then check.
- **Break it** steps are deliberate mistakes. Do them: reading errors is the admin's main skill.
- Stuck inside a program? Press `q`, then `Ctrl+C`, then `Esc` `Esc` `:q!` `Enter`.

### Values used in the files

| Placeholder | Example | Yours |
|---|---|---|
| `[user]` / `trainee01` | `trainee01` | given by the trainer |
| `[vm-ip]` | `10.0.0.5` | `ip addr` (Topic 10) |
| `[neighbour-ip]` | `10.0.0.6` | ask your neighbour |

### The PayBank story (Part B)

> PayBank runs its portal on one Linux server: **Apache** on port 80 in front, a **Tomcat**-style app server on port 8080 running `payment-service`.
> At **09:13** payments stopped. Part B sections investigate it piece by piece; topic 16 solves the whole incident.

Build or reset the lab server any time:

```bash
bash ~/01-linux/setup-lab.sh
```
