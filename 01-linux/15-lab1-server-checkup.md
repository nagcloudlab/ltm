# 15 · Lab 1 · Server check-up


Do every step. Write the answer in the table. Use only commands from this guide.

| # | Task | Command(s) | Your answer |
|---|---|---|---|
| 1 | Back up the ssh config | `cd /etc/ssh ; tar -czf ~/ssh.tar.gz sshd_config ; tar -tzf ~/ssh.tar.gz` | file name inside: |
| 2 | Find the Port setting | `grep -n "Port 22" /etc/ssh/sshd_config` | line number of `#Port 22`: |
| 3 | Process, service, port | `pgrep -a cron` · `systemctl status cron` · `sudo ss -lntp` | cron PID: · does cron have a port? |
| 4 | Resources | `nproc` · `free -h` · `df -h` · `sudo du -sh /var/log/* \| sort -h` | cores / available / Use% / biggest: |
| 5 | Who logged in? | `sudo grep -c "Accepted" /var/log/auth.log` | count: |
| 6 | **Break it:** a service | `sudo systemctl stop cron` → `status` → `journalctl -u cron -n 5` → `start` | what did the journal say? |
| 7 | **Break it:** a port | `nc -vz localhost 2222` → refused → explain with `sudo ss -lntp` | why refused? |

**Fast finishers:**

- Extract `~/ssh.tar.gz` into `~/practice` and compare with the original: `diff ~/practice/sshd_config /etc/ssh/sshd_config` (no output = identical). (`diff` is taught in Topic 03.)
- Show only the real settings in sshd_config: `grep -v "^#" /etc/ssh/sshd_config | grep -v "^$"` (`^#` = line starts with #, `^$` = empty line).
