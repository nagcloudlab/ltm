# Linux for Middleware Admins · One-page cheat sheet

## Where am I, what is here
| | |
|---|---|
| `pwd` · `cd /path` · `cd ..` · `cd` | where / go / up / home |
| `ls -lah` · `ls -lt \| head` | everything / newest first |
| `whoami` · `hostname` · `id` · `uname -r` · `cat /etc/os-release` | who, which server, which OS |

## Read
| | |
|---|---|
| `wc -l f` | how many lines (check before cat) |
| `cat -n f` · `less f` | small file / big file (`/word`, `G`, `F`, `q`) |
| `head -n 20 f` · `tail -n 20 f` · `tail -F f` | start / end / follow live |
| `zcat f.gz \| …` · `zgrep x f.gz` | read compressed logs |

## Search and count
| | |
|---|---|
| `grep -c -i -n -v -w x f` | count, ignore case, line no., invert, whole word |
| `grep -B 3 -A 2 x f` · `grep -C 5` | context before/after |
| `grep -E "A\|B" f` · `grep -o "re" f` · `grep -rl x dir` | or / only match / which files |
| `cut -d' ' -f9` · `awk '{print $4}'` · `awk '$9>=500'` | pick columns, filter rows |
| `sort \| uniq -c \| sort -rn \| head` | **most common** |

## Find and compare
| | |
|---|---|
| `find . -name "*.log"` · `-type d` · `-size +100M` · `-mtime +30` · `-mmin -60` | find by name/type/size/age |
| `find … -exec ls -lh {} \;` | act on each (run without action first!) |
| `diff a b` · `diff -u a b` · `diff -y --suppress-common-lines a b` | what changed |

## Processes
| | |
|---|---|
| `top` (`P` `M` `1` `q`) · `ps aux --sort=-%cpu \| head` · `ps -ef` | who is busy / who started it |
| `pgrep -af name` · `kill PID` · `kill -9 PID` (last) · `kill -0 PID` | find / stop / force / alive? |
| `cmd &` · `jobs` · `Ctrl+Z` · `bg` · `fg` · `nohup cmd > log 2>&1 &` | background jobs |

## Health
| | |
|---|---|
| `nproc` · `uptime` · `free -h` (watch **available**) | CPU, load, memory |
| `df -h` · `df -i` · `sudo du -sh /var/* \| sort -h` | disk, inodes, which folder |
| `lsof +L1` · `truncate -s 0 f` | deleted-but-open files / empty a live log |

## Services and logs
| | |
|---|---|
| `systemctl status \| start \| stop \| restart \| reload \| enable x` | services |
| `journalctl -u x -n 50` · `-f` · `--since "1 hour ago"` | service log |
| `/var/log/syslog` · `/var/log/auth.log` · `/var/log/apache2/` · `/var/log/nginx/` | log files |

## Network
| | |
|---|---|
| `ip addr` · `sudo ss -lntp` · `getent hosts name` | IP, who listens, name → IP |
| `ping -c 3 host` · `nc -vz host port` · `curl -I url` | machine / port / HTTP |
| refused = service · timed out = network/firewall | |

## Files, owners, packages
| | |
|---|---|
| `cp -r` · `mv` · `rm -i` · `mkdir -p` · `touch` | files |
| `chmod 644 / 755 / 600` · `sudo chown user:group f` | permissions |
| `sudo apt update && sudo apt install -y x` | install |
| `tar -czf a.tar.gz dir` · `-tzf` · `-xzf` · `gzip f` | archive |

## Remote
| | |
|---|---|
| `ssh user@host 'cmd'` · `ssh-keygen -t ed25519` · `ssh-copy-id user@host` | run remotely, keys |
| `scp f host:/tmp/` · `scp -r` · `-P port` | copy |
| `rsync -avzn src/ host:dst/` then without `-n` | sync (dry run first) |

## Environment and scripts
| | |
|---|---|
| `echo $PATH` · `which x` · `type x` · `export VAR=v` · `source ~/.bashrc` | environment |
| `alias ll='ls -lah'` | shortcut |
| `#!/usr/bin/env bash` · `set -euo pipefail` · `$1` `$?` · `bash -x s.sh` | scripts |
| `crontab -e` · `*/5 * * * *` · escape `\%` · full paths | schedule |

## Redirection
| | |
|---|---|
| `> f` replace · `>> f` append · `2> f` errors · `2>&1` both · `\| tee -a f` screen + file | |

## Advanced
| | |
|---|---|
| `sudo systemctl daemon-reload` · `systemctl cat x` · `systemctl show -p NRestarts,MainPID x` | after unit changes / see all files / numbers |
| `/etc/systemd/system/x.service.d/override.conf` · `Restart=on-failure` · `LimitNOFILE=` | drop-in, restart policy, open files |
| `journalctl -u x --since "10 min ago" -p err -o short-iso` · `journalctl -p err -b` | filter by unit, time, priority |
| `systemctl list-timers` · `OnCalendar=daily` | timers |
| `iostat -xz 2 3` · `pidstat 2 3` · `sar -u 2 3` (package sysstat) | disk / process / CPU stats |
| `grep "open files" /proc/PID/limits` · `ls /proc/PID/fd \| wc -l` | open-file limit and use |
| `sudo dmesg -T \| grep -i "killed process"` | OOM killer |
| `ss -tan state established '( sport = :8085 )'` · `sudo lsof -i :8085` | connections on one port |
| `getent hosts n` (like apps) vs `dig +short n` (DNS only) · `curl --resolve n:port:ip` | name problems |
| `curl -w "%{time_connect} %{time_starttransfer}\n"` | network vs server time |
| `timedatectl` · `TZ=Asia/Kolkata date -d "… UTC"` | clock, zone, convert |
| `openssl x509 -in c.crt -noout -enddate` · `-checkend 2592000` | certificate expiry |
| `logger -t tag -p user.err "msg"` | write a test log line |

## Message → first command
| | |
|---|---|
| `203/EXEC` | `systemctl cat x \| grep ExecStart` + `ls -l` |
| `Address already in use` | `sudo ss -ltnp '( sport = :PORT )'` |
| `No space left on device` | `df -h`, then `df -i` |
| `Too many open files` | `/proc/PID/limits` |
| cron silent | `grep CRON /var/log/syslog` |
| ssh key ignored | `sudo grep sshd /var/log/auth.log` |

## Incident order
**read logs → find the time → find the cause → save evidence → fix what is ours → verify (`curl`, `tail -F`) → escalate the rest → report**
