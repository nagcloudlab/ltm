# 13 · Remote access: ssh keys, scp, rsync

**Time:** 30 min

**Practise on** the PayBank lab server (`~/lab/srv`, built by `00-setup.md`) and your own lab VM.


---

---

# Practice

```bash
cd ~/lab/srv
```

- **No partner?** Use your own VM as "B": in 13.3 write `HostName localhost` and your own user name. Every command then works the same.

## 13.1 · Log in, and run one command remotely

```bash
ssh trainee02@10.0.0.6
ssh trainee02@10.0.0.6 'hostname; uptime; df -h / | tail -1'
```

Quoted commands run on B and the output comes back to A. Great for quick checks.

| Option | Means |
|---|---|
| `ssh -p 2222 user@host` | ssh on another port |
| `ssh -v user@host` | verbose: shows each step, for "why can't I connect?" |
| `ssh user@host 'cmd'` | run one command, then leave |

### When ssh fails

| Message | Means | Check |
|---|---|---|
| `Connection refused` | nothing listens on port 22 | `systemctl status ssh` on B |
| `Connection timed out` | blocked on the way | firewall / network team (Topic 10) |
| `Permission denied (publickey,password)` | wrong user or password | user name, password |
| `REMOTE HOST IDENTIFICATION HAS CHANGED!` | the server's key changed (rebuilt VM, or an attack) | confirm with the server owner, then `ssh-keygen -R 10.0.0.6` |

## 13.2 · Keys: no password, more secure

```
A (your VM)                                  B (neighbour)
~/.ssh/id_ed25519      private key: NEVER leaves A
~/.ssh/id_ed25519.pub  public key ──copy──► ~/.ssh/authorized_keys
```

### Step 1 · create a key pair on A

```bash
ssh-keygen -t ed25519 -C "trainee01@lab-vm-01"
ls -l ~/.ssh/
```

The private key is `600` (only you). If it is not, ssh refuses to use it.

### Step 2 · copy the public key to B

```bash
ssh-copy-id trainee02@10.0.0.6
```

### Step 3 · log in without a password

```bash
ssh trainee02@10.0.0.6
```

> Keys still not used? Permissions on B: `~/.ssh` must be `700`, `authorized_keys` `600`. `ssh -v` shows which key was offered.

## 13.3 · A shortcut file: `~/.ssh/config`

```bash
cat >> ~/.ssh/config <<'EOF'
Host vm2
    HostName 10.0.0.6
    User trainee02
    Port 22
EOF
chmod 600 ~/.ssh/config
ssh vm2 hostname
```

## 13.4 · scp: copy one file or folder

```bash
scp ~/lab/srv/etc/payment/app-prod.properties vm2:/tmp/
scp vm2:/etc/hostname ./b-hostname.txt
scp -r ~/lab/srv/etc vm2:/tmp/lab-etc
```

```
scp   SOURCE                               DESTINATION
      local file  ───────────────────────► host:/path      (upload)
      host:/path  ───────────────────────► local file      (download)
```

| Option | Means |
|---|---|
| `-r` | a whole folder |
| `-P 2222` | port (capital P for scp!) |
| `-p` | keep times and permissions |

## 13.5 · rsync: copy only what changed

```bash
rsync -avz ~/lab/srv/var/log/ vm2:/tmp/a-logs/
rsync -avz ~/lab/srv/var/log/ vm2:/tmp/a-logs/      # run again
```

| Option | Means |
|---|---|
| `-a` | archive: recursive, keep permissions, times, links |
| `-v` | list what is copied |
| `-z` | compress on the way |
| `-n` | **dry run**: show what would happen, copy nothing |
| `--delete` | delete files on the destination that are gone from the source |
| `--progress` | per-file progress |

> **Trailing slash matters.** `rsync src/ dst/` copies the **contents** of src into dst. `rsync src dst/` creates `dst/src/`. Always try `-n` first, especially with `--delete`.

### Typical middleware uses

```bash
rsync -avz vm2:/etc/hosts ./b-hosts.txt
rsync -av etc/apache2/sites-available/portal.conf vm2:/tmp/
```

## 13.6 · sftp: interactive (know it exists)

```bash
sftp vm2
```

At the `sftp>` prompt, type:

```
ls /tmp
get /etc/hostname
put etc/payment/app-prod.properties /tmp/
bye
```

> **FTP** (port 21) sends passwords in plain text. Never use it on company networks; use sftp, scp or rsync over ssh.

---

## Exercises

1. Without logging in, find how many CPU cores B has and how much memory is available.
2. Copy B's `/etc/os-release` to your home folder as `b-os.txt`, then `diff` it with yours.
3. Use `rsync -n` to see what would be copied from `~/lab/srv/opt` to `vm2:/tmp/opt`. Then copy it for real.
4. Your colleague says "scp -p 2222 file host:" fails. Why?

## Answers

1. `ssh vm2 'nproc; free -h | grep Mem'`.
2. `scp vm2:/etc/os-release ~/b-os.txt && diff /etc/os-release ~/b-os.txt` (usually identical).
3. `rsync -avzn ~/lab/srv/opt/ vm2:/tmp/opt/` then without `-n`.
4. scp uses capital `-P` for the port; small `-p` means "preserve times".
