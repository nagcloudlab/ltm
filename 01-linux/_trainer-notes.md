# Trainer notes

- **Before the session:** on one VM, confirm `systemctl is-active cron` = `active`, `curl` and `nc` are installed (`which curl nc`), and every VM can ping its neighbour.
- **Timing:** Part A of Topics 01–05 ≈ 75 min, Part A of Topics 06–11 ≈ 75 min, Lab 1 (file 15) 20 min. Break after Topic 05. Part B sections: afternoon practice block or Day 2 warm-up.
- **Common snags:**
  - Stuck in `less`, `top`, `man`, or `systemctl status`: press `q`.
  - Stuck in vi: `Esc` `Esc` `:q!`.
  - `Permission denied` on `/var/log/auth.log`: add `sudo`.
  - Topic 09 second login fails: password-less keys may be configured; ask students to use `ssh -o PubkeyAuthentication=no trainee01@localhost` to force a password prompt.
  - Topic 10 neighbour ping times out: VMs may be on separate networks; use the trainer VM's IP instead.
- **Reset a student's practice folder:** `rm -rf ~/practice ~/restore ~/practice.tar.gz ~/ssh.tar.gz` (check the prompt first).
- **Topics 17–21 (advanced):** need `python3` (on every Ubuntu server), `sysstat` (17/18 install it), internet for `apt` and for 19.4/19.6. Topic 17 creates `/opt/paysim` and the `paysim` service; 18, 19 and 21 use it. Remove afterwards: `sudo systemctl disable --now paysim; sudo rm -r /etc/systemd/system/paysim* /opt/paysim; sudo systemctl daemon-reload`.
- **Topic 21 pairs:** the partner runs the Break block; the other may use only the Read commands until they can say the cause. Scenario 10 = two breaks at once (good pair: 1 + 7, or 2 + 8).
- **Snag:** `pkill -f` with a pattern that also appears in your own command line kills your shell's command too; use the PID from `ss -p`.
- **Snag:** `ssh` in 21.8 uses `BatchMode=yes` so it never hangs on a password prompt.
