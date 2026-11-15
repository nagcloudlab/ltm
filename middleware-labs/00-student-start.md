# Student start — prepare your Ubuntu laptop

**Time:** 15–20 minutes. **Starting point:** Ubuntu Desktop 24.04 LTS, internet access for GitHub and Ubuntu packages, a normal sudo-capable account, at least 2 CPU cores, 4 GB RAM and 20 GB free disk. You work directly on your laptop. No SSH connection or virtual machine is needed.

## 1. Open a terminal on your Ubuntu laptop

Press **Ctrl+Alt+T**. Run every lab command in this local terminal as your normal sudo-capable account. Open a second terminal window when a guide asks you to follow logs alongside requests.

```bash
whoami
hostname
cat /etc/os-release
uname -m
sudo -v
```

Expected: Ubuntu 24.04 and either `x86_64` or `aarch64`. Your browser, curl and all middleware services run on the same laptop. `localhost` and `127.0.0.1` mean this laptop.

## 2. Install common administration tools

```bash
sudo apt update
sudo apt install -y git curl ca-certificates unzip tar vim apache2-utils iproute2 netcat-openbsd
mkdir -p ~/lab ~/lab/evidence ~/lab/backups
```

You do not need Maven, an IDE, or Java source files. The JRE is installed when Tomcat is introduced.

## 3. Clone the GitHub repository on your Ubuntu laptop

Run these in your local terminal:

```bash
cd ~
git clone https://github.com/nagcloudlab/ltm.git ~/ltm
cd ~/ltm/middleware-labs/project-files
sha256sum -c SHA256SUMS
ls web apps config kong downloads
```

Expected: all checksum checks report `OK`; `apps` includes the prepared `payment.war` and `payment-broken.war`. No archive download, SCP transfer, or application build is needed. A private repository requires your own GitHub access.

If you already cloned this repository into `~/ltm`, update it instead of cloning again:

```bash
cd ~/ltm
git status --short
git pull --ff-only
cd ~/ltm/middleware-labs/project-files
sha256sum -c SHA256SUMS
```

If Git reports conflicting local changes or a checksum fails, stop and inspect the difference before continuing. Do not discard your work with `git reset --hard`.

Use the reference files in the clone as supplied. Each guide copies configurations into `/etc` and deploys files under `/var/www` or `/opt/tomcat`; make practice edits at those installed locations. Evidence and backups go under `~/lab/`, outside Git. This keeps `git pull --ff-only` straightforward.

Pulling updates changes repository files only. It does not automatically update a running service: review the revised guide, copy the relevant file, validate, and reload or restart as instructed. Keep the same commit as your study group during a session:

```bash
cd ~/ltm
git rev-parse --short HEAD
```

## 4. Check ports before installing services

```bash
sudo ss -lntp
sudo ufw status
```

Ports 80, 8081, 8080, 8000 and 8001 must be available for the lab. If another application already uses a port, identify it before proceeding; do not stop an unfamiliar service or overwrite an existing website.

All requests in these guides stay on your own laptop. Use `localhost`, `127.0.0.1`, or the local name `portal.example.test` configured in Lab 1. You do not need to open inbound firewall ports or configure cloud networking.

## 5. Start your evidence notebook

```bash
cp ~/ltm/middleware-labs/project-files/web/health.txt ~/lab/evidence/project-files-verified.txt
date -Is | tee ~/lab/evidence/start-time.txt
```

For each incident, record: command, status, timestamp, relevant log line, failing hop, recovery and successful retest. Use [the worksheet](06-student-evidence.md).

**Ready:** go to [Lab 1 — Apache](01-apache.md).
