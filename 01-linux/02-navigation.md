# 02 · Navigation: folders and paths

**Time:** 25 min

**Part A · Basics** on your own lab VM. **Part B · In depth** on the PayBank lab server (`~/lab/srv`, built by `00-setup.md`).


---

# Part A · Basics

## 02.1 · Folders and moving around


Linux has **one tree** starting at `/`. No `C:` or `D:`.

| Folder | Holds |
|---|---|
| `/home/trainee01` (`~`) | your own files |
| `/etc` | settings (configuration files) |
| `/var/log` | logs |
| `/tmp` | scratch space, may be emptied on reboot |
| `/opt` · `/usr` · `/proc` · `/run` | hand-installed software · programs · live process info · runtime files |

```bash
pwd
cd /var/log
pwd
ls
cd ..
pwd
cd
pwd
```

| Command | Meaning |
|---|---|
| `pwd` | print working directory: where am I? |
| `cd /var/log` | go to a **full path** (starts with `/`) |
| `cd ..` | go **up** one level |
| `cd` or `cd ~` | go **home** |

### Full path or relative path

```
/
└── home
    └── trainee01
        ├── notes    ← you are here
        └── backup
```

| Path | Starts from | Example |
|---|---|---|
| full | `/` (works from anywhere) | `cd /home/trainee01/backup` |
| relative | where you are now | `cd ../backup` (`..` = one level up) |

### ls options

```bash
ls -a
ls -lh /etc/hosts
ls -lt /var/log            # newest at the top
```

| Option | Meaning |
|---|---|
| `-l` | long list, one line per file |
| `-a` | all, including hidden files (start with `.`) |
| `-h` | human sizes: K, M, G |
| `-t` | newest first |

### Read one ls -l line

```
-rw-r--r-- 1 root root 221 Nov 11 09:12 /etc/hosts
│└───┬───┘ │ └┬─┘ └┬─┘ └┬┘ └─────┬────┘ └───┬────┘
│    │     │  │    │    │        │          └ name
│    │     │  │    │    │        └ last changed
│    │     │  │    │    └ size (bytes)
│    │     │  │    └ group
│    │     │  └ owner
│    │     └ links (ignore for now)
│    └ permissions: owner | group | others
└ type:  - file   d folder   l link
```

### Try it yourself

1. Go to `/etc` using a full path.
2. List it long, newest first. Which file changed most recently?
3. Go to `/etc/ssh` using a **relative** path from `/etc`.
4. Go back home in one command.


---

# Part B · In depth: the PayBank lab server

```bash
cd ~/lab/srv
```

## 02.2 · Wildcards: many files at once

```bash
ls /etc/*.conf | head -n 5
ls /var/log/*.log
ls /var/log/syslog*
ls /etc/ssh/ssh_host_*_key.pub
ls /var/log/apt/????ory.log
```

| Pattern | Matches |
|---|---|
| `*` | any characters, any number (also none) |
| `?` | exactly one character |
| `[0-9]` | one digit |
| `{a,b}` | `a` or `b`: `ls /etc/{hosts,hostname}` |

The **shell** expands the pattern before the command runs. Test any pattern with `echo` first: `echo /var/log/*.log` shows exactly which files a later `rm` would hit.

## 02.3 · Jump back and forth: `cd -`

```bash
cd ~/lab/srv/etc/apache2/sites-available
cd ~/lab/srv/var/log/apache2
cd -
cd -
```

`cd -` swaps between the last two folders: config folder ↔ log folder, all day long.

## 02.4 · What kind of file is it? `file` and `stat`

```bash
file /etc/hosts /usr/bin/ls /usr/share/man/man1/ls.1.gz /etc/ssh
stat /etc/hosts
```

Linux does not care about extensions. `file` reads the content and tells you what it really is: before you `cat` something, check it is text.

## 02.5 · Links: one file, two names (`ln -s`)

Apache and Nginx enable websites with **symbolic links**. Practise here first:

```bash
cd ~/practice
echo "real content" > real.txt
ln -s real.txt shortcut.txt
ls -l
cat shortcut.txt
rm real.txt
cat shortcut.txt
ls -l shortcut.txt              # a broken link: it points nowhere now
```

```
shortcut.txt  ──points to──►  real.txt  (the data)
```

| Fact | Means for you |
|---|---|
| type letter `l`, arrow `->` | it is a link |
| delete the link | the real file is untouched |
| delete the real file | the link breaks (often shown in red) |
| `readlink -f name` | prints the final real path |

```bash
readlink -f /bin/sh
ls -l /etc/alternatives/editor
```

## 02.6 · See the tree: `tree` and `du`-free browsing

```bash
sudo apt install -y tree            # if not installed
tree -L 2 /etc/ssh
tree -d -L 1 /var                   # folders only, one level
```

---

## Exercises

1. In `ls -l /etc`, is `ssh` a file or a folder? How do you know?
2. Show every `.conf` file directly in `/etc` whose name starts with `s`.
3. Which real program runs when you type `sh`?
4. Is `/usr/share/man/man1/ls.1.gz` text? Prove it.
5. In `~/practice` make a link `today.log` that points to `/var/log/syslog`. Can you read it with `tail`? Why or why not?

## Answers

1. A folder: the line starts with `d`.
2. `ls /etc/s*.conf`
3. `readlink -f /bin/sh` → `/usr/bin/dash`.
4. `file /usr/share/man/man1/ls.1.gz` → gzip compressed data, not text; read it with `zcat`.
5. `ln -s /var/log/syslog ~/practice/today.log; tail today.log` → works only if your user is in the group `adm` (check with `id`); otherwise `Permission denied`. The link itself always works: permissions belong to the **real** file.
