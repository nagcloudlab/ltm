# 14 · Shell scripting

**Time:** 50 min

**Practise on** the PayBank lab server (`~/lab/srv`, built by `00-setup.md`) and your own lab VM.


---

---

# Practice

Keep your scripts in `~/scripts` (the lab reset does not touch it):

```bash
mkdir -p ~/scripts
cd ~/scripts
```

- Every script below: create it with `vi name.sh`, paste the text, save with `:wq`, then `chmod 755 name.sh`.

## 14.1 · First script

```bash
vi hello.sh
```

```bash
#!/usr/bin/env bash
# hello.sh: my first script
echo "Server: $(hostname)"
echo "User:   $(whoami)"
echo "Time:   $(date '+%F %T')"
```

```bash
chmod 755 hello.sh
./hello.sh
```

| Part | Means |
|---|---|
| `#!/usr/bin/env bash` | "run me with bash" (the shebang: must be line 1) |
| `#` | comment |
| `$(cmd)` | run `cmd`, put its output here |
| `./hello.sh` | run the file in this folder (`.` is not in PATH) |

**Break it:** remove the `x` permission (`chmod 644 hello.sh`) and run `./hello.sh` → `Permission denied`. `bash hello.sh` still works, because bash reads it as a text file.

## 14.2 · Variables and arguments

```bash
#!/usr/bin/env bash
# svc.sh: show a service's state.  Usage: ./svc.sh apache2
SERVICE=$1                               # first argument
if [ -z "$SERVICE" ]; then
    echo "Usage: $0 <service>"
    exit 1
fi
STATE=$(systemctl is-active "$SERVICE")
echo "$SERVICE is $STATE"
```

```bash
chmod 755 svc.sh
./svc.sh cron
./svc.sh
echo $?
```

| Variable | Holds |
|---|---|
| `$0` | the script's name |
| `$1`, `$2` … | arguments |
| `$#` | how many arguments |
| `$@` | all arguments |
| `$?` | exit code of the last command: **0 = success**, anything else = failure |

> **No spaces around `=`.** `SERVICE = $1` tries to run a command called `SERVICE`.
> **Always quote variables:** `"$SERVICE"`. Unquoted, an empty or spaced value breaks the command.

## 14.3 · Decisions: `if`

```bash
if [ condition ]; then
    …
elif [ other ]; then
    …
else
    …
fi
```

| Test | True when |
|---|---|
| `[ -f file ]` | file exists |
| `[ -d dir ]` | folder exists |
| `[ -z "$v" ]` / `[ -n "$v" ]` | empty / not empty |
| `[ "$a" = "$b" ]` / `!=` | strings equal / differ |
| `[ $n -eq 5 ]` | numbers: `-eq -ne -gt -ge -lt -le` |
| `cmd && echo ok` | run echo only if cmd succeeded |
| `cmd \|\| echo failed` | run echo only if cmd failed |

### Real example: web health check

```bash
#!/usr/bin/env bash
# webcheck.sh: is a URL answering 200?  Usage: ./webcheck.sh http://localhost/
URL=${1:-http://localhost/}
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL")

if [ "$CODE" = "200" ]; then
    echo "OK    $URL  ($CODE)"
elif [ "$CODE" = "000" ]; then
    echo "DOWN  $URL  (no answer: refused or timed out)"
    exit 2
else
    echo "WARN  $URL  (HTTP $CODE)"
    exit 1
fi
```

```bash
chmod 755 webcheck.sh
./webcheck.sh http://localhost/          # Apache, after Module 3
./webcheck.sh http://localhost:9999/
```

`curl` prints `000` when it never got an HTTP answer at all: the refused/timed-out cases from Topic 10.

## 14.4 · Loops

### Over a list

```bash
for svc in ssh cron apache2 nginx; do
    printf "%-10s %s\n" "$svc" "$(systemctl is-active $svc)"
done
```

```
ssh        active
cron       active
apache2    active
nginx      inactive
```

### Over files

```bash
for f in ~/lab/srv/var/log/apache2/*.log ~/lab/srv/opt/tomcat/logs/*.out; do
    echo "$(wc -l < "$f") lines  $f"
done
```

### Over numbers: which ports are open?

```bash
for port in 22 80 443 8080 8081; do
    if nc -z -w 1 localhost $port 2>/dev/null; then
        echo "port $port OPEN"
    else
        echo "port $port closed"
    fi
done
```

### while: wait until a service is up (used after every restart)

```bash
#!/usr/bin/env bash
# waitfor.sh: wait up to 60 s for a URL.  Usage: ./waitfor.sh http://localhost:8080/
URL=$1
for i in $(seq 1 12); do
    if curl -s -o /dev/null --max-time 2 "$URL"; then
        echo "UP after $(( (i-1) * 5 )) s"
        exit 0
    fi
    echo "waiting… ($i/12)"
    sleep 5
done
echo "still DOWN after 60 s"
exit 1
```

`$(( … ))` does arithmetic.

## 14.5 · Functions

```bash
log() { echo "$(date '+%F %T') [$1] $2"; }

log INFO  "check started"
log ERROR "payment-service not running"
```

```
2026-08-24 10:15:02 [INFO] check started
2026-08-24 10:15:02 [ERROR] payment-service not running
```

## 14.6 · The real one: `morning-check.sh`

```bash
#!/usr/bin/env bash
# morning-check.sh: one-page health report for a middleware server
# Usage: ./morning-check.sh [report-file]
set -euo pipefail

REPORT=${1:-/dev/stdout}
LAB=$HOME/lab/srv
DISK_LIMIT=80

log()  { echo "$(date '+%T') $*" >> "$REPORT"; }
line() { echo "------------------------------------------" >> "$REPORT"; }

check_services() {
    for s in ssh cron apache2 nginx; do
        log "service  $(printf '%-8s' $s) $(systemctl is-active $s || true)"
    done
}

check_disk() {
    local used
    used=$(df --output=pcent / | tail -1 | tr -dc '0-9')
    if [ "$used" -gt "$DISK_LIMIT" ]; then
        log "DISK     / at ${used}%  ** above ${DISK_LIMIT}% **"
    else
        log "disk     / at ${used}%"
    fi
}

check_memory() {
    log "memory   available $(free -h | awk '/Mem:/ {print $7}') of $(free -h | awk '/Mem:/ {print $2}')"
}

check_errors() {
    local f=$LAB/opt/tomcat/logs/catalina.out
    [ -f "$f" ] || { log "app log  not found"; return; }
    log "app log  ERROR=$(grep -c ERROR "$f" || true)  FATAL=$(grep -c FATAL "$f" || true)"
    grep FATAL "$f" | tail -n 3 | while read -r l; do log "   $l"; done
}

check_locks() {
    find "$LAB/run" -name "*.lock" 2>/dev/null | while read -r l; do
        log "LOCK     $l (age $(( ( $(date +%s) - $(stat -c %Y "$l") ) / 60 )) min)"
    done
}

check_5xx() {
    local a=$LAB/var/log/apache2/access.log
    log "web 5xx  $(awk '$9 >= 500' "$a" | wc -l) of $(wc -l < "$a") requests"
}

line; log "MORNING CHECK  $(hostname)"; line
check_services
check_disk
check_memory
check_5xx
check_errors
check_locks
line
```

```bash
chmod 755 morning-check.sh
./morning-check.sh
./morning-check.sh ~/morning-$(date +%F).txt      # save to a file
```

Small commands used here for the first time:

| Command | Does |
|---|---|
| `printf '%-8s' x` | print `x` padded to 8 characters (neat columns) |
| `tr -dc '0-9'` | delete every character that is not a digit (`" 36%"` → `36`) |
| `stat -c %Y file` | the file's last-change time in seconds |
| `date +%s` | now, in seconds; subtract to get an age |
| `awk '/Mem:/ {print $7}'` | on the line containing `Mem:`, print field 7 |

| Line | Why it is there |
|---|---|
| `set -e` | stop at the first failing command |
| `set -u` | stop if a variable is used but never set (catches typos) |
| `set -o pipefail` | a pipe fails if **any** part fails, not only the last |
| `\|\| true` | "this command may fail and that is fine" (e.g. `grep -c` finds 0) |
| `local` | variable visible only inside the function |
| `while read -r l` | handle a list one line at a time |

Run it every morning at 08:00 from cron (Topic 08):

```
0 8 * * * $HOME/scripts/morning-check.sh $HOME/morning-$(date +\%F).txt
```

## 14.7 · Debugging

```bash
bash -x ./svc.sh cron
```

Every line is printed (with `+`) before it runs, with variables already filled in. Put `set -x` … `set +x` around just the part you suspect.

| Mistake | Symptom |
|---|---|
| `X = 5` | `X: command not found` |
| missing `then` / `fi` | `syntax error near unexpected token` |
| `[ $a = b ]` when `a` is empty | `unary operator expected`: quote it, `"$a"` |
| Windows line endings (file edited on a laptop) | `/usr/bin/env: 'bash\r': No such file` → `sed -i 's/\r$//' script.sh` |

---

## Exercises

1. Write `count5xx.sh` that takes an access-log path and prints how many 5xx answers it has. Exit 1 if more than 10.
2. Extend the port loop to read ports from the command line: `./ports.sh 22 80 8080`.
3. Add a `check_config_drift` function to `morning-check.sh` that compares `portal.conf` with `backup/portal.conf.bak` and logs `CONFIG CHANGED` if they differ.
4. Run `morning-check.sh` with `bash -x` and find the line where `DISK_LIMIT` is compared.

## Answers

1. ```bash
   #!/usr/bin/env bash
   N=$(awk '$9 >= 500' "$1" | wc -l)
   echo "5xx: $N"
   [ "$N" -gt 10 ] && exit 1 || exit 0
   ```
   On the lab log: `5xx: 14`, exit 1.
2. Replace the list with `"$@"`: `for port in "$@"; do …`.
3. ```bash
   check_config_drift() {
       diff -q "$LAB/backup/portal.conf.bak" "$LAB/etc/apache2/sites-available/portal.conf" >/dev/null \
         && log "config   portal.conf unchanged" \
         || log "CONFIG CHANGED  portal.conf (run diff -u to see)"
   }
   ```
   and call `check_config_drift` before the last `line`.
4. `bash -x ./morning-check.sh 2>&1 | grep -e '-gt'` → `+ '[' 6 -gt 80 ']'` (your disk % differs). `grep DISK_LIMIT` finds only the line `+ DISK_LIMIT=80`: in the comparison, `bash -x` already shows the **values**, not the names.
