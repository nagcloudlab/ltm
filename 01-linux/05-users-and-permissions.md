# 05 · Users and permissions

**Time:** 20 min

**Part A · Basics** on your own lab VM. **Part B · In depth** on the PayBank lab server (`~/lab/srv`, built by `00-setup.md`).


---

# Part A · Basics

## 05.1 · Users and permissions


```bash
id
cat /etc/shadow
sudo head -n 2 /etc/shadow
```

`sudo` = run **one** command as root. Every sudo is logged (you will see it in Topic 09).

### Read a permission string

```
-rw-r--r--
│└┬┘└┬┘└┬┘
│ │  │  └ others: r--  read only
│ │  └─── group:  r--  read only
│ └────── owner:  rw-  read + write
└──────── type: - file
```

| Letter | File | Folder |
|---|---|---|
| `r` = 4 | read it | list it |
| `w` = 2 | change it | add/delete inside |
| `x` = 1 | run it | enter it (`cd`) |

| Number | String | Typical use |
|---|---|---|
| 644 | `rw-r--r--` | normal file |
| 755 | `rwxr-xr-x` | folder, script |
| 600 | `rw-------` | private file |

### Lock yourself out, then let yourself in

```bash
cd ~/practice
ls -l hosts.txt
chmod 000 hosts.txt
cat hosts.txt
chmod 644 hosts.txt
cat hosts.txt                    # works again
```

### Folder x permission

```bash
mkdir secret
echo "hi" > secret/file.txt
chmod 644 secret                 # no x
cat secret/file.txt
chmod 755 secret
cat secret/file.txt
```

### Change owner (needs sudo)

```bash
sudo chown root hosts.txt
ls -l hosts.txt
echo "x" >> hosts.txt
sudo chown trainee01 hosts.txt   # give it back
```


---

# Part B · In depth: the PayBank lab server

```bash
cd ~/lab/srv
```

## 05.2 · Groups: sharing access without sharing passwords

```bash
id
groups www-data
getent group sudo
```

```
user trainee01 ──member of──► groups: trainee01, sudo
file rw-r----- root adm  →  owner root: rw · group adm: r · others: nothing
```

Log files are often owned by the group **adm** so admins can read them without sudo:

```bash
ls -l /var/log/syslog
cat /var/log/syslog | head -n 1
sudo usermod -aG adm trainee01         # -a append, -G group
exit                                   # groups apply at the next login
ssh trainee01@[vm-ip]
id
head -n 1 /var/log/syslog              # works now, no sudo
```

> **Always `-aG`.** `usermod -G adm` (without `a`) **replaces** all groups: you lose `sudo`.

## 05.3 · Test as the web server user: `sudo -u`

Module 3's 403 errors come from **www-data** not being able to read a file. Test as that user directly:

```bash
mkdir -p ~/practice/site
echo "hello" > ~/practice/site/index.html
sudo -u www-data cat ~/practice/site/index.html
ls -ld ~
```

Your home folder is `750`: "others" (www-data) cannot enter it, so nothing inside can be served. That is why websites live in `/var/www`, not in home folders.

```bash
sudo mkdir -p /var/www/test
sudo cp ~/practice/site/index.html /var/www/test/
sudo -u www-data cat /var/www/test/index.html
```

## 05.4 · chmod with letters

Make four practice files first:

```bash
cd ~/practice
touch script.sh file secret.txt notice.txt
mkdir -p shared/docs
```

```bash
chmod u+x script.sh        # owner: add run
chmod g-w file             # group: remove write
chmod o= secret.txt        # others: nothing
chmod a+r notice.txt       # all: add read
chmod -R g+rX shared       # folder tree: group read, X = enter folders only
ls -l
```

| Who | | What | |
|---|---|---|---|
| `u` | user (owner) | `+` / `-` / `=` | add / remove / set exactly |
| `g` | group | `r w x` | read write run |
| `o` | others | `X` | run/enter **only** for folders |
| `a` | all | | |

## 05.5 · New files get default permissions: `umask`

```bash
umask
touch new.txt ; mkdir newdir ; ls -ld new.txt newdir
```

`umask` removes permissions from new files. Services usually set `0022` (files 644, folders 755).

## 05.6 · Change owner of a whole tree

```bash
sudo chown -R www-data:www-data /var/www/test      # owner AND group, everything inside
ls -l /var/www/test
```

Module 3 warns: for website files, `root` owner + `644/755` is safer than `www-data` owner. Use `chown -R` for **data** folders the app must write to (uploads, Tomcat's `logs/`, `work/`).

## 05.7 · What may I run with sudo?

```bash
sudo -l
sudo grep trainee01 /var/log/auth.log | grep COMMAND | tail -n 3
```

Every sudo is written to `auth.log`: who, when, which command.

---

## Exercises

1. Convert `rwxr-x---` to a number. Who can read it?
2. Which groups does `syslog` belong to? Which group owns `/var/log/auth.log`?
3. Give the group `rw` on `~/practice/hosts.txt` and others nothing, using letters.
4. Prove `www-data` can read `/var/www/test/index.html` but not `/etc/shadow`.
5. Why does a site in `/home/trainee01/site` return 403 even with `644` files?

## Answers

1. 750. The owner (rwx) and the group (r-x) can read; others cannot.
2. `id syslog`; `ls -l /var/log/auth.log` → group `adm`.
3. `chmod g=rw,o= ~/practice/hosts.txt`.
4. `sudo -u www-data cat /var/www/test/index.html` works; `sudo -u www-data cat /etc/shadow` → Permission denied.
5. `/home/trainee01` is `750`: www-data (others) has no `x` on the folder, so it cannot enter it.
