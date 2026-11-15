# Student start — prepare your Ubuntu laptop

- **Needs:** Ubuntu Desktop 24.04 LTS, internet access (GitHub, Ubuntu packages), a normal sudo-capable account, 2+ CPU cores, 4 GB RAM, 20 GB free disk
- **You build:** a ready laptop with tools, the cloned repository and an evidence folder
- You work directly on the laptop: no SSH or virtual machine needed.

## 1. Open a terminal on your Ubuntu laptop

- Press **Ctrl+Alt+T**. Run every lab command here as your normal account.
- Open a second terminal when a guide asks you to follow logs.

Show your user:

```bash
whoami
```

Show the machine name:

```bash
hostname
```

Show the OS version:

```bash
cat /etc/os-release
```

Show the CPU architecture:

```bash
uname -m
```

Confirm sudo works:

```bash
sudo -v
```

- **Expected:** Ubuntu 24.04 and `x86_64` or `aarch64`.
- Browser, curl and all services run on this laptop: `localhost` and `127.0.0.1` mean this laptop.

## 2. Install common administration tools

Refresh package lists:

```bash
sudo apt update
```

Install the tools:

```bash
sudo apt install -y git curl ca-certificates unzip tar vim apache2-utils iproute2 netcat-openbsd
```

Create the lab folders:

```bash
mkdir -p ~/lab ~/lab/evidence ~/lab/backups
```

- No Maven, IDE or Java source needed. The JRE is installed in the Tomcat lab.

## 3. Clone the GitHub repository on your Ubuntu laptop

- Already cloned (e.g. from the README)? Skip to **Update an existing clone** — a second clone stops with `fatal: destination path ... already exists`.

Go to your home folder:

```bash
cd ~
```

Clone the repository:

```bash
git clone https://github.com/nagcloudlab/ltm.git ~/ltm
```

Enter the project files:

```bash
cd ~/ltm/middleware-labs/project-files
```

Verify checksums:

```bash
sha256sum -c SHA256SUMS
```

List the supplied folders:

```bash
ls web apps config kong downloads
```

- **Expected:** every checksum reports `OK`; `apps` includes `payment.war` and `payment-broken.war`.
- No archive download, SCP or build needed. A private repository needs your own GitHub access.

**Update an existing clone** instead of cloning again.

Go to the repository:

```bash
cd ~/ltm
```

Check for local changes:

```bash
git status --short
```

Pull updates:

```bash
git pull --ff-only
```

Enter the project files:

```bash
cd ~/ltm/middleware-labs/project-files
```

Verify checksums:

```bash
sha256sum -c SHA256SUMS
```

- **If it fails** (conflicting local changes or a failed checksum): stop and inspect the difference. Do not discard work with `git reset --hard`.
- Use the reference files as supplied. Guides copy them into `/etc`, `/var/www` or `/opt/tomcat`; make practice edits there. Evidence and backups go in `~/lab/`, outside Git — so `git pull --ff-only` stays simple.
- Pulling changes repository files only, not running services: review the revised guide, copy the file, validate, then reload or restart as instructed.
- Stay on the same commit as your study group during a session.

Go to the repository:

```bash
cd ~/ltm
```

Show the current commit:

```bash
git rev-parse --short HEAD
```

## 4. Check ports before installing services

List listening ports:

```bash
sudo ss -lntp
```

Check the firewall:

```bash
sudo ufw status
```

- Ports 80, 8081, 8080, 8000 and 8001 must be free.
- If another application uses one, identify it first; do not stop an unfamiliar service or overwrite an existing website.
- All requests stay on your laptop (`localhost`, `127.0.0.1`, or `portal.example.test` from Lab 1). No inbound firewall ports or cloud networking needed.

## 5. Start your evidence notebook

Record that project files are verified:

```bash
cp ~/ltm/middleware-labs/project-files/web/health.txt ~/lab/evidence/project-files-verified.txt
```

Record the start time:

```bash
date -Is | tee ~/lab/evidence/start-time.txt
```

- For each incident record: command, status, timestamp, relevant log line, failing hop, recovery, successful retest. Use [the worksheet](06-student-evidence.md).

**Ready:** go to [Lab 0 — Linux skills](00-linux-skills.md), or straight to [Lab 1 — Apache](01-apache.md) if you are comfortable on the Linux command line.
