# 04 · The vi editor

**Time:** 15 min

**Part A · Basics** on your own lab VM. **Part B · In depth** on the PayBank lab server (`~/lab/srv`, built by `00-setup.md`).


---

# Part A · Basics

## 04.1 · Editing with vi


vi has **modes**:

```
            i                 :
  NORMAL ─────────► INSERT     NORMAL ─────────► COMMAND
  (keys = commands)  (typing)   ◄───────────     (:w :q …)
            ◄─────────              Enter
               Esc
```

Lost? Press `Esc` twice. You are back in NORMAL.

### The habit: back up, edit, check

```bash
cd ~/practice
cp hosts.txt hosts.txt.bak
vi hosts.txt
```

Inside vi:

| Keys | Does |
|---|---|
| `G` | go to the last line |
| `o` | open a new line below and start typing |
| type `10.0.0.9 myserver` | |
| `Esc` | stop typing |
| `:wq` `Enter` | write and quit |

```bash
tail -n 2 hosts.txt
```

### More keys to practise

| Keys | Does |
|---|---|
| `/localhost` `Enter` | search; `n` for next |
| `dd` | delete the current line |
| `u` | undo |
| `:set nu` | show line numbers |
| `:q!` | quit and **throw away** changes |

**Break it, then recover:**

1. `vi hosts.txt`, press `dd` five times, then `:wq`. The file is damaged.
2. Restore it: `cp hosts.txt.bak hosts.txt`
3. Check: `cat hosts.txt`


---

# Part B · In depth: the PayBank lab server

```bash
cd ~/lab/srv
```

## 04.2 · Move fast in a big file

| Keys (NORMAL mode) | Does |
|---|---|
| `gg` / `G` | first line / last line |
| `:120` `Enter` | go to line 120 |
| `w` / `b` | next / previous word |
| `0` / `$` | start / end of the line |
| `Ctrl+f` / `Ctrl+b` | page down / up |
| `/Listen` then `n` / `N` | search forward, next / previous |

```bash
vi +14 /etc/ssh/sshd_config          # open directly at line 14
vi -R /etc/ssh/sshd_config           # read-only: safe for looking
```

## 04.3 · Copy, cut, paste

| Keys | Does |
|---|---|
| `yy` | copy (yank) the line |
| `3yy` | copy 3 lines |
| `dd` / `5dd` | cut 1 / 5 lines |
| `p` / `P` | paste below / above |
| `x` | delete one character |
| `.` | repeat the last change |
| `u` / `Ctrl+r` | undo / redo |

Practise: `cp /etc/hosts ~/practice/h2 ; vi ~/practice/h2`, copy the first line with `yy`, `G`, `p`. Save with `:wq`.

## 04.4 · Find and replace in the whole file

```
:%s/localhost/127.0.0.1/g          every match, every line
:%s/8080/8090/gc                   ask before each change (y/n)
:5,10s/^/# /                       comment out lines 5 to 10
```

| Part | Means |
|---|---|
| `%` | all lines (`5,10` = only those) |
| `s/old/new/` | substitute |
| `g` | every match on the line, not just the first |
| `c` | confirm each one |

This is how admins change a port in a config file in seconds.

## 04.5 · Line numbers and spotting mistakes

```
:set nu            show line numbers (Apache and Nginx errors name a line)
:set nonu          hide them
:set list          show hidden characters ($ = end of line, ^I = Tab)
```

`:set list` reveals stray spaces and Tabs that break YAML files (Kong in Module 8).

## 04.6 · "Swap file exists": vi was interrupted

```
E325: ATTENTION
Found a swap file by the name ".sshd_config.swp"
…
[O]pen Read-Only, (E)dit anyway, (R)ecover, (D)elete it, (Q)uit, (A)bort:
```

Someone (maybe you, in a dropped ssh session) is still editing, or vi crashed.

| Choice | When |
|---|---|
| `Q` quit | someone else may be editing: ask first |
| `R` recover | your session dropped; get your unsaved work back |
| `D` delete | you are sure nobody else is editing |

---

## Exercises

1. You typed `:wq` but the text `:wq` appeared inside your file. Which mode were you in, and what should you have pressed first?
2. Open `~/practice/hosts.txt` read-only directly at its last line.
3. Replace every `localhost` with `LOCALHOST` in `~/practice/hosts.txt`, confirming each one.
4. Comment out lines 2 to 4 of `~/practice/h2` in one command.
5. You see `E325: ATTENTION` on a production config. What do you do first?

## Answers

1. INSERT mode. Press `Esc` first, then `:wq`.
2. `vi -R + ~/practice/hosts.txt` (`+` alone = last line), or `vi -R` then `G`.
3. `:%s/localhost/LOCALHOST/gc`, then `:wq`.
4. `:2,4s/^/# /`
5. Press `Q`, then find out who else is logged in and editing (`who`, `ps -ef | grep vi`) before touching it.
