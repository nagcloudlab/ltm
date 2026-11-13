# 03 · Files: create, copy, read, find, compare

**Time:** 60 min

**Part A · Basics** on your own lab VM. **Part B · In depth** on the PayBank lab server (`~/lab/srv`, built by `00-setup.md`).

**You will learn in Part B:** `wc`, `cat -n`, reading a slice with `head | tail` (the pipe `|` is formally taught in 06), `tail -F`, `less` keys, `find`, `-exec`, `diff`, `paste`, `touch -t`

---

# Part A · Basics

## 03.1 · Files and folders


All practice happens in `~/practice`. Nothing outside it is changed.

```bash
cd ~
mkdir -p practice
cd practice
mkdir -p a/b/c          # -p makes the parents too
touch empty.txt         # empty file
ls -R
```

### Put text into a file: `>` and `>>`   

```bash
echo "first line" > notes.txt     # > creates or REPLACES the file
echo "second line" >> notes.txt   # >> ADDS to the end
cat notes.txt
```

> Careful: `>` on an existing file wipes it. Never use `>` on a log.

### Several commands on one line: `;`

```bash
cd ~/practice ; ls
```

`;` runs the commands one after another.

### Copy, move, rename

```bash
cp /etc/hosts hosts.txt      # copy a real system file, safely
cp hosts.txt hosts.bak       # backup copy
mv notes.txt todo.txt        # rename
mv todo.txt a/               # move into a folder
cp -r a a-copy               # copy a whole folder: needs -r
ls
```

**Break it:**

```bash
cp a a-copy2
```

Read the message: it tells you exactly what is missing.

### Read files

```bash
cat hosts.txt                    # whole file (small files only)
head -n 3 /etc/services          # first 3 lines
tail -n 3 /etc/services          # last 3 lines
less /etc/services               # page by page
```

Inside `less`: `Space` next page · `b` back · `/ssh` search · `n` next match · `q` quit.

### Delete (carefully)

```bash
pwd                              # ALWAYS check where you are first
rm hosts.bak
rm -i a-copy/todo.txt
rm -r a-copy                     # a folder and everything in it
ls
```

> **There is no recycle bin.** `rm` is permanent. Before any `rm` on a real server: check the prompt, run `pwd`, run `ls`.


---

# Part B · In depth: the PayBank lab server

```bash
cd ~/lab/srv
```

## 03.2 · How big is each log? (`wc`)

Never `cat` a file before you know its size.

```bash
wc -l var/log/apache2/access.log opt/tomcat/logs/catalina.out var/log/apache2/error.log
ls -lh opt/tomcat/logs/
```

| Command | Counts |
|---|---|
| `wc -l` | lines |
| `wc -w` | words |
| `wc -c` | bytes |

> **Rule:** `catalina.out` (1.5 K) is safe to `cat`. `catalina.2026-08-23.log` (120 M) is not: `cat` would flood your screen for minutes. Use `head`, `tail`, `less` or `grep` on big files.

## 03.3 · The whole story, start to end (`cat`)

```bash
cat opt/tomcat/logs/catalina.out
```

`cat -n` adds line numbers, useful when you tell a colleague "look at line 13".

```bash
cat -n opt/tomcat/logs/catalina.out | head -n 16 | tail -n 5
```

## 03.4 · How did the day start? (`head`)

```bash
head -n 3 opt/tomcat/logs/catalina.out
```

The app started cleanly at 09:00. Whatever broke, broke later.

## 03.5 · What is happening now? (`tail`)

```bash
tail -n 4 opt/tomcat/logs/catalina.out
tail -n 5 var/log/apache2/access.log
```

| | head | tail |
|---|---|---|
| shows | the start | the end |
| default | 10 lines | 10 lines |
| use for | "how did it start?" | "what is happening now?" |

### A slice from the middle

```bash
head -n 16 opt/tomcat/logs/catalina.out | tail -n 4     # lines 13 to 16
```

## 03.6 · Watch it live (`tail -f`)

Open a **second terminal** (ssh in again).

Terminal 1:

```bash
tail -f ~/lab/srv/opt/tomcat/logs/catalina.out
```

Terminal 2, pretend to be the app writing new lines:

```bash
echo "2026-08-24 09:21:00 INFO  [startup] Manual restart requested by trainee01" >> ~/lab/srv/opt/tomcat/logs/catalina.out
echo "2026-08-24 09:21:05 ERROR [startup] Restart blocked: lock file exists" >> ~/lab/srv/opt/tomcat/logs/catalina.out
```

Each line appears in Terminal 1 the moment it is written. Stop with `Ctrl+C`.

Put the lab back to its original state, so the counts in later topics match:

```bash
bash ~/01-linux/setup-lab.sh > /dev/null
cd ~/lab/srv
```

| Option | Does |
|---|---|
| `tail -f` | follow: keep printing new lines |
| `tail -F` | follow even if the file is rotated (renamed and recreated): use this for real logs |
| `tail -n 50 -f` | show the last 50, then follow |

> **`>>` vs `>`:** `>>` adds to the end. `>` would **wipe** the log and write one line. Never use `>` on a log.

## 03.7 · Page through a big file (`less`)

```bash
less opt/tomcat/logs/catalina.out
```

| Key | Does |
|---|---|
| `Space` / `b` | next / previous page |
| `G` / `g` | end / start of file |
| `/FATAL` `Enter` | search forward; `n` next, `N` previous |
| `?WARN` | search backward |
| `-N` | toggle line numbers |
| `F` | follow like `tail -f`; `Ctrl+C` to stop following |
| `q` | quit |

`less` opens a 120 MB file instantly, because it reads only the page you look at. `cat` reads all of it.

## 03.8 · find by name

```bash
find . -name "*.properties"
find . -name "*.lock"
find . -iname "CATALINA*"           # -iname ignores capitals
```

```
find  .      -name "*.lock"
│     │      └── test: name ends in .lock (* = anything; quote it!)
│     └── where to start (. = here)
└── the command
```

> Always quote the pattern. Unquoted, the shell expands `*.lock` itself before find sees it.

## 03.9 · find by type

```bash
find . -type d | wc -l          # folders
find . -type f -name "*.gz"     # files ending .gz
```

| `-type` | Means |
|---|---|
| `f` | regular file |
| `d` | directory (folder) |
| `l` | symbolic link |

## 03.10 · find by size (disk cleanup)

```bash
find . -type f -size +10M
```

| Size | Means |
|---|---|
| `+10M` | more than 10 MB |
| `-1k` | less than 1 KB |
| `+1G` | more than 1 GB |

## 03.11 · find by age

```bash
touch -d "40 days ago" var/log/payment/archived/app.log.2026-08-15.gz
find . -name "*.gz" -mtime +30
find . -mmin -60          # changed in the last 60 minutes
```

| Test | Means |
|---|---|
| `-mtime +30` | modified **more than** 30 days ago |
| `-mtime -1` | in the last day |
| `-mmin -60` | in the last 60 minutes ("what changed just before the outage?") |

- Ran the setup script less than an hour ago? Then `-mmin -60` lists almost everything: every lab file is new.

## 03.12 · Do something with every result (`-exec`)

```bash
find . -type f -size +10M -exec ls -lh {} \;
```

```
-exec ls -lh {} \;
      │      │  └── end of the command (the backslash protects ; from the shell)
      │      └── {} = replaced by each file found
      └── the command to run
```

```bash
find etc -name "*.properties" -exec head -n 1 {} \;
```

> **Danger:** `find … -delete` or `-exec rm {} \;` deletes without asking. Always run the same `find` **without** the action first, read the list, then add the action.

## 03.13 · diff: what is different between prod and staging?

```bash
diff etc/payment/app-prod.properties etc/payment/app-staging.properties
```

| Symbol | Means |
|---|---|
| `<` | line from the **first** file |
| `>` | line from the **second** file |
| `3c3` | line 3 **c**hanged; `a` added, `d` deleted |

### Side by side, only differences

```bash
diff -y --suppress-common-lines etc/payment/app-prod.properties etc/payment/app-staging.properties
```

**Finding:** production has a pool of **20** and a heap of **512 MB**. Staging, where testing passed, has 100 and 2048 MB. That matches the FATAL lines exactly.

### What changed in the Apache site file?

```bash
diff -u backup/portal.conf.bak etc/apache2/sites-available/portal.conf
```

`-u` (unified) is the format used in change tickets and Git: `-` removed, `+` added. Someone changed the DocumentRoot; that will cause 404s on the portal.

```bash
diff -q backup/portal.conf.bak etc/apache2/sites-available/portal.conf
```

## 03.14 · paste: two columns into one table

```bash
cut -d= -f2 etc/payment/app-prod.properties    > /tmp/prod.txt
cut -d= -f2 etc/payment/app-staging.properties > /tmp/stg.txt
cut -d= -f1 etc/payment/app-prod.properties    > /tmp/keys.txt
paste /tmp/keys.txt /tmp/prod.txt /tmp/stg.txt | column -t | grep -v '^#'
```

- `cut -d= -f2` = take the part after `=` (fully explained in Topic 09.15).
- `grep -v '^#'` = drop lines starting with `#` (Topic 09.10).
- `column -t` lines up the columns. This is a ready-made table for your incident report.

## 03.15 · touch: create files and change their time

```bash
touch run/maintenance.flag                   # empty marker file
touch -t 202608240913 run/maintenance.flag   # set time to 2026-08-24 09:13
ls -l --time-style=long-iso run/
```

Apps often check for a marker file ("if maintenance.flag exists, show the maintenance page"). Timestamps matter because `find -mtime` and backups depend on them.

---

## Exercises

1. You ran `mv hosts.txt servers.txt`. How many files exist now: one or two?
2. How many requests are in the Apache access log?
3. What time did the app server start, and on which port?
4. Show only the last 3 lines of Apache's error log. Which component wrote the very last line?
5. Without `cat`, show lines 5 to 8 of `catalina.out`.
6. In `less`, find the first `FATAL`. What line number is it on?
7. Which command would you use to watch Apache's access log during a test, and why `-F` rather than `-f`?
8. Find every `.war` file under `~/lab/srv`.
9. Find files larger than 50 MB and show their sizes.
10. Prove nobody changed `app-prod.properties` in the last 10 minutes.

## Answers

1. One. `mv` renames; `hosts.txt` no longer exists.
2. `wc -l var/log/apache2/access.log` → **30** (plus any lines you added).
3. `head -n 1 opt/tomcat/logs/catalina.out` → **09:00:01, port 8080**.
4. `tail -n 3 var/log/apache2/error.log` → `authz_core`.
5. `head -n 8 opt/tomcat/logs/catalina.out | tail -n 4`.
6. `less`, then `-N`, then `/FATAL` → **line 13**.
7. `tail -F var/log/apache2/access.log`. `-F` keeps following after nightly log rotation renames the file.
8. `find . -name "*.war"` → `payment.war`, `portal.war`.
9. `find . -size +50M -exec ls -lh {} \;` → heapdump (60M), catalina.2026-08-23.log (120M).
10. `find etc/payment -mmin -10` prints nothing (unless you ran setup in the last 10 minutes).
