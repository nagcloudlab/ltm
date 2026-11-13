# 01 · Log in, the shell, commands

**Time:** 20 min

**Part A · Basics** on your own lab VM. **Part B · In depth** on the PayBank lab server (`~/lab/srv`, built by `00-setup.md`).

**You will learn in Part B:** which shell exactly, `/bin/sh` vs bash

---

# Part A · Basics

## 01.1 · Log in


From your laptop open a terminal (Windows: PowerShell or Windows Terminal; Mac: Terminal).

```bash
ssh trainee01@10.0.0.5
```

The first time, ssh asks `Are you sure you want to continue connecting (yes/no)?` Type `yes`.

```bash
whoami
hostname
cat /etc/os-release
uname -r
```

| Command | Answers the question |
|---|---|
| `whoami` | which user am I? |
| `hostname` | which machine am I on? |
| `cat /etc/os-release` | which Linux (distro) and version? |
| `uname -r` | which kernel version? |


## 01.2 · The shell, commands and the prompt


```bash
echo $SHELL
```

Your shell is **bash**. It reads what you type and asks the kernel to run it.

### A command has three parts

```
ls      -l       /etc
│       │        └── argument: what to do it to
│       └── option: how to do it (starts with -)
└── command: what to do
```

Spaces separate the parts. Capitals matter: `LS` is not `ls`.

Read your prompt, piece by piece:

```
trainee01@lab-vm-01:~$
   │         │      │ └── $ = normal user   (# would mean root: be careful)
   │         │      └──── ~ = your home folder
   │         └─────────── which machine
   └───────────────────── who you are
```

### Five keys to use from now on

| Key | Does | Try it now |
|---|---|---|
| `Tab` | completes names | type `cd /et` then press `Tab` |
| `↑` / `↓` | earlier commands | press `↑` three times |
| `Ctrl+C` | stops the running command | run `ping 127.0.0.1`, then `Ctrl+C` |
| `Ctrl+L` | clears the screen | press it |
| `--help` / `man` | help for a command | `ls --help`, then `man ls` (`q` to quit) |

```bash
history
```


## 01.3 · Same skills on Red Hat


| Task | Ubuntu (our lab) | Red Hat · Rocky |
|---|---|---|
| install software | `apt install` | `dnf install` |
| firewall | `ufw status` | `firewall-cmd --list-all` |
| main log | `/var/log/syslog` | `/var/log/messages` |
| extra guard | AppArmor | SELinux: can block even when permissions look fine |
| **same** | systemctl, journalctl, ps, top, ss, vi, grep, tar, chmod | |

---

# Part B · In depth: the PayBank lab server

```bash
cd ~/lab/srv
```

## 01.4 · Which shell?

```bash
echo $SHELL               # your login shell
echo $0                   # the shell running right now
cat /etc/shells
ls -l /bin/sh
```

On Ubuntu `sh` is really **dash**, a small fast shell. A script starting `#!/bin/sh` runs in dash, so bash-only features may fail there. Start your scripts with `#!/usr/bin/env bash` or `#!/bin/bash`.

---

## Exercises

1. Which family is your distro in, and which line told you?
2. What does the prompt look like when you are in `/var/log`? (Predict, then check in Topic 02.)

## Answers

1. Debian family. The line `ID_LIKE=debian` in `/etc/os-release`.
2. `trainee01@lab-vm-01:/var/log$`
