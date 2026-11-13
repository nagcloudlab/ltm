# 12 · Environment: variables, PATH, aliases

**Time:** 30 min

**Practise on** the PayBank lab server (`~/lab/srv`, built by `00-setup.md`) and your own lab VM.


---

---

# Practice

```bash
cd ~/lab/srv
```

## 12.1 · Environment variables

```bash
env | head
echo $HOME $USER $HOSTNAME
```

| Variable | Holds |
|---|---|
| `HOME` | your home folder (`~`) |
| `USER` | your user name |
| `PATH` | folders searched for commands |
| `PWD` | current folder |
| `LANG` | language and character set |
| `JAVA_HOME` | the Java install (set for Tomcat, Module 5) |
| `TZ` | time zone override |

## 12.2 · PATH: how `ls` is found

```bash
echo $PATH
which curl
type cd ls
```

The shell checks each folder **left to right** and runs the **first** match.

```
you type: java
   │
   ▼  /usr/local/sbin/java?  no
      /usr/local/bin/java?   no
      /usr/sbin/java?        no
      /usr/bin/java?         YES → runs /usr/bin/java
```

### "command not found" fixed

```bash
mkdir -p ~/bin
printf '#!/bin/bash\necho "status: payment OK"\n' > ~/bin/paycheck
chmod 755 ~/bin/paycheck
paycheck
export PATH="$PATH:$HOME/bin"
paycheck
```

> Keep `$PATH` in the new value. `export PATH=$HOME/bin` (without `$PATH:`) removes every other folder and breaks `ls`, `cat`, everything. If that happens: `export PATH=/usr/bin:/bin` and log out.

## 12.3 · Shell variable vs exported variable

```bash
APP=payment-service                 # shell variable (no spaces around =)
echo $APP
bash -c 'echo "child sees: $APP"'
export APP
bash -c 'echo "child sees: $APP"'
```

```
your shell            programs you start from it
APP=x       ──────►   cannot see APP
export APP  ──────►   can see APP
```

Tomcat's start script, Java and every program you launch are **children**. They see only **exported** variables.

### One-off: set a variable for one command only

```bash
date
TZ=UTC date
TZ=Asia/Kolkata date
```

- If your server already runs in UTC, the first two lines match; the third shows Indian time.

Handy for reading IIS logs, which are in UTC (Module 4).

## 12.4 · JAVA_HOME for middleware

Java is not on a fresh server. Install it first (Tomcat needs it later anyway):

```bash
sudo apt install -y openjdk-21-jre-headless
```

- `ls /usr/lib/jvm/` shows the exact folder name; on Intel/AMD machines it ends in `-amd64`, on ARM machines in `-arm64`.

```bash
ls /usr/lib/jvm/
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
echo $JAVA_HOME
$JAVA_HOME/bin/java -version
```

| Problem | Typical cause |
|---|---|
| Tomcat: "Neither the JAVA_HOME nor the JRE_HOME environment variable is defined" | `JAVA_HOME` not set or not exported **for the service** |
| works from your shell, fails under systemd | systemd does not read your `.bashrc`; set `Environment=JAVA_HOME=…` in the unit file (Module 5) |
| wrong Java version runs | another `java` earlier in `PATH`: `which -a java` |

## 12.5 · Make it permanent: `~/.bashrc`

Variables set by typing vanish when you log out.

```bash
cp ~/.bashrc ~/.bashrc.bak
cat >> ~/.bashrc <<'EOF'

# --- middleware lab ---
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export PATH="$PATH:$HOME/bin"
export LAB=$HOME/lab/srv
EOF
source ~/.bashrc         # load it now, without logging out
echo $LAB
```

| File | Read when | Put here |
|---|---|---|
| `~/.bashrc` | every new interactive bash | aliases, PATH, your variables |
| `~/.profile` | login (ssh in) | Ubuntu's `.profile` loads `.bashrc` anyway |
| `/etc/environment` | every login, all users | system-wide simple `KEY=value` lines |
| unit file `Environment=` | when systemd starts a service | **service** settings |

## 12.6 · Useful variable tricks

```bash
echo ${DB_HOST:-localhost}       # use a default if not set
DB_HOST=prod-db-01 ; echo ${DB_HOST:-localhost}
unset DB_HOST
[ -z "$DB_HOST" ] && echo "DB_HOST is empty"
echo "Log: ${APP}.log"           # braces when text follows
```

## 12.7 · Aliases: shortcuts

```bash
alias ll='ls -lah'
alias logs='cd /var/log && ls -lt | head'
alias aplog='sudo tail -f /var/log/apache2/error.log'
alias ports='sudo ss -lntp'
ll
alias               # list all
unalias logs
```

Add the ones you like to `~/.bashrc` to keep them.

> On someone else's server, `ll` or `rm` may be an alias that does something unexpected. `type rm` tells you.

---

## Exercises

1. Show where `systemctl`, `ss` and `tar` live.
2. Make a variable `ENV=staging`. Prove a child `bash -c` cannot see it, then export it and prove it can.
3. What time is it in UTC right now? (one command)
4. Add an alias `chk` that runs `systemctl is-active apache2 nginx cron` and make it survive logout.
5. Somebody ran `export PATH=/opt/app/bin`. Now `ls` says command not found. Fix the session in one line.

## Answers

1. `which systemctl ss tar` → `/usr/bin/…`.
2. `ENV=staging; bash -c 'echo $ENV'` (empty) → `export ENV; bash -c 'echo $ENV'` → `staging`.
3. `TZ=UTC date` (or `date -u`).
4. `echo "alias chk='systemctl is-active apache2 nginx cron'" >> ~/.bashrc && source ~/.bashrc`.
5. `export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin` (or just log out and in).
