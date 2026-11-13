# 11 · Software and archives

**Time:** 20 min

**Part A · Basics** on your own lab VM. **Part B · In depth** on the PayBank lab server (`~/lab/srv`, built by `00-setup.md`).

**You will learn in Part B:** archiving a log folder with a date in the name, `tar -C`

---

# Part A · Basics

## 11.1 · Software: apt and tar


```bash
sudo apt update
sudo apt install -y tree
tree ~/practice
```

### Pack and unpack

```bash
cd ~
tar -czf practice.tar.gz practice      # c create, z gzip, f file
ls -lh practice.tar.gz
tar -tzf practice.tar.gz               # t list contents
mkdir restore
cd restore
tar -xzf ../practice.tar.gz            # x extract
ls
```


---

# Part B · In depth: the PayBank lab server

```bash
cd ~/lab/srv
```

## 11.2 · Archive a whole folder (with a date)

```bash
tar -czf ~/archived-logs-$(date +%F).tar.gz -C var/log/payment archived
tar -tzf ~/archived-logs-*.tar.gz
rm -r var/log/payment/archived       # only AFTER checking the tar list
```

| Option | Means |
|---|---|
| `-c` / `-x` / `-t` | create / extract / list |
| `-z` | gzip compress |
| `-f name` | archive file name |
| `-C dir` | change into `dir` first (so paths inside start at `archived/`) |
| `$(date +%F)` | today as `2026-08-24`: dated file names |

## 11.3 · Find and inspect packages

```bash
apt search nginx 2>/dev/null | head -n 4
apt show nginx 2>/dev/null | grep -E "^(Version|Depends)"
apt list --installed 2>/dev/null | grep -E "^(openssh-server|curl)/"
```

## 11.4 · Which package owns this file?

```bash
dpkg -S /usr/sbin/sshd
dpkg -L tree | head -n 5           # files a package installed
dpkg -l | grep -E "^ii\s+(apache2|nginx) "
```

"Who installed this config file?" → `dpkg -S`. Essential before deleting anything under `/etc` or `/usr`.

## 11.5 · Versions: what will be installed, and holding one

```bash
apt-cache policy openssh-server
sudo apt-mark hold openssh-server
apt-mark showhold
sudo apt-mark unhold openssh-server
```

On production, middleware packages are often **held** so an `apt upgrade` cannot change Apache or Java without a change ticket.

## 11.6 · Remove, purge, and the history of changes

```bash
sudo apt remove -y tree       # remove program, keep its config files
sudo apt purge -y tree        # remove program AND its config
sudo apt autoremove -y        # remove helper packages nobody needs now
grep -E "Commandline|Start-Date" /var/log/apt/history.log | tail -n 6
```

`/var/log/apt/history.log` answers "who installed or upgraded what, and when?": the first file to read after "it broke after last night's patching".

---

## Exercises

1. Which letter in `tar -czf` means "create", and which means "the file name comes next"?
2. Which package provides the `ss` command?
3. What version of `curl` is installed, and is a newer one available?
4. Hold `curl`, prove it is held, unhold it.
5. When did you install `tree`, according to apt's own log?

## Answers

1. `c` = create, `f` = file name follows (`z` = compress with gzip).
2. `dpkg -S $(which ss)` → `iproute2`.
3. `apt-cache policy curl`: compare Installed with Candidate.
4. `sudo apt-mark hold curl; apt-mark showhold; sudo apt-mark unhold curl`.
5. `grep -B1 "install -y tree" /var/log/apt/history.log`.
