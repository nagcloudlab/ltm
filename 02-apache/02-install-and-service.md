# 02 · Install Apache and manage the service

**Time:** 35 min

**You will learn:** prove nothing listens yet, install Apache, prove it works with three checks, stop/start/restart/reload, the configtest habit, auto-start at boot, `systemctl` vs `apache2ctl`, opening it from your laptop, and the `ufw` firewall.

---

## 02.1 · Before: nothing is listening on port 80

```bash
curl -I http://localhost
sudo ss -lntp | grep ':80 '
dpkg -l | grep apache2
```

| Command | Expect now |
|---|---|
| `curl -I` | `curl: (7) Failed to connect to localhost port 80 … Couldn't connect to server`: the door is closed (connection refused) |
| `ss` | no line for `:80` |
| `dpkg -l` | nothing: not installed |

## 02.2 · Install

```bash
sudo apt update
sudo apt install -y apache2
```

| What Ubuntu did | Check it |
|---|---|
| installed packages `apache2`, `apache2-bin`, `apache2-data`, `apache2-utils` | `dpkg -l \| grep apache2` |
| created the service `apache2` | `systemctl status apache2` |
| **started** it and **enabled** it at boot | `systemctl is-active apache2 ; systemctl is-enabled apache2` |
| opened port 80 | `sudo ss -lntp \| grep apache2` |
| created a default page | `ls -l /var/www/html/` |

```bash
apache2 -v
```

(On Red Hat the same software is called `httpd`: `dnf install httpd`, then `systemctl enable --now httpd` yourself.)

## 02.3 · curl: the admin's browser

| Command | Shows |
|---|---|
| `curl URL` | the body (the page) |
| `curl -I URL` | headers only: is it answering, and how? |
| `curl -v URL` | the whole conversation (topic 10) |
| `curl -o file URL` | save the page into a file |
| `curl -s URL` | silent, for scripts |
| `curl -s -o /dev/null -w "%{http_code}\n" URL` | only the status code |

```bash
curl -I http://localhost
curl -s http://localhost | head -n 5
curl -s -o /dev/null -w "%{http_code}\n" http://localhost
```

## 02.4 · Three checks prove a service works

```bash
systemctl status apache2 --no-pager
sudo ss -lntp | grep ':80 '
curl -I http://localhost
```

| # | Check | Question |
|---|---|---|
| 1 | process | is it alive? |
| 2 | port | is the door open? |
| 3 | answer | does it reply with a status? |

> **Running is not working.** Only check 3 proves it works. Stop at the first check that fails; that is where the problem is.

## 02.5 · Open it from your laptop

```bash
ip -4 addr show | grep inet
```

On your laptop browser open `http://[vm-ip]/`. You see **Apache2 Default Page · It works!** That page is the file `/var/www/html/index.html`:

```bash
head -n 20 /var/www/html/index.html
```

Times out from the laptop but works with curl on the VM? That is a firewall question (02.9).

## 02.6 · Stop and start: the full life cycle

```bash
sudo systemctl stop apache2
systemctl is-active apache2
curl -I http://localhost
sudo systemctl start apache2
systemctl is-active apache2
curl -I http://localhost
```

| State | `is-active` | curl |
|---|---|---|
| stopped | `inactive` | `Couldn't connect to server` |
| started | `active` | `200 OK` |

## 02.7 · Restart vs reload

Watch a long download while you restart, in **two terminals**.

Terminal 1: make a 50 MB file and download it slowly:

```bash
sudo fallocate -l 50M /var/www/html/big.bin
curl --limit-rate 1M -o /dev/null http://localhost/big.bin
```

Terminal 2, while Terminal 1 is still downloading:

```bash
sudo systemctl reload apache2
```

Terminal 1 keeps downloading. Start the download again, and this time:

```bash
sudo systemctl restart apache2
```

Terminal 1 fails: `curl: (18) transfer closed` or similar.

| | `reload` | `restart` |
|---|---|---|
| does | re-reads config; old workers finish their requests | stops everything, then starts |
| visitors | not cut off | in-flight requests **dropped** |
| use for | site and config changes | module changes (`a2enmod`), upgrades, when reload is not enough |
| broken config | old config **keeps running** | Apache **does not come back** |

```bash
sudo rm /var/www/html/big.bin
```

## 02.8 · The habit: test before reload

```bash
sudo apache2ctl configtest
```

- `Syntax OK` → safe to reload. Anything else names the file and line.
- On a fresh VM you also see a warning above `Syntax OK`:

Sample line:

```text
AH00558: apache2: Could not reliably determine the server's fully qualified domain name, using 10.0.0.5. Set the 'ServerName' directive globally to suppress this message
```

- It is only a **warning**: Apache does not know its own name.
- Give the server a name once, in its own small config file, and switch that file on with `a2enconf`:

```bash
echo "ServerName localhost" | sudo tee /etc/apache2/conf-available/servername.conf
sudo a2enconf servername
sudo apache2ctl configtest && sudo systemctl reload apache2
```

- Now configtest prints only `Syntax OK`.
- `a2enconf` / `a2disconf` switch extra config files on and off (topic 03 shows the folders).

**Break it:**

```bash
sudo cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf.bak
echo "ThisIsNotADirective on" | sudo tee -a /etc/apache2/apache2.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
systemctl status apache2 --no-pager | head -n 5
curl -I http://localhost
```

Sample line (configtest):

```text
AH00526: Syntax error on line 226 of /etc/apache2/apache2.conf:
Invalid command 'ThisIsNotADirective', perhaps misspelled or defined by a module not included in the server configuration
```

- configtest names the file, the line number and the bad word.
- The reload fails (`Job for apache2.service failed.`), **but Apache keeps serving the old config**: status still says `active (running)` and curl still gets 200. A `restart` now would take the website down. Restore:

```bash
sudo cp /etc/apache2/apache2.conf.bak /etc/apache2/apache2.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
```

`&&` = run the reload **only if** configtest succeeded. Use this pair every time.

## 02.9 · Auto-start at boot

```bash
systemctl is-enabled apache2
sudo systemctl disable apache2
systemctl is-enabled apache2
sudo systemctl enable apache2
```

| Command | Effect |
|---|---|
| `enable` / `disable` | start at boot or not (does **not** start/stop now) |
| `enable --now` | enable **and** start now |
| `is-enabled` | `enabled` / `disabled` |

After every server patching reboot, the first check is: did all enabled services come back?

```bash
systemctl list-units --type=service --state=failed
```

## 02.10 · Two tools: systemctl and apache2ctl

| `systemctl …` (the service) | | `apache2ctl …` (Apache's own tool) | |
|---|---|---|---|
| `status apache2` | alive? | `configtest` | check the files |
| `reload apache2` | re-read config | `-S` | list websites |
| `restart apache2` | stop + start | `-M` | list modules |
| `enable apache2` | start at boot | `-v` / `-V` | version / build settings |

Rule: **systemctl** to change its state, **apache2ctl** to ask it questions.

## 02.11 · Firewall: ufw

There can be two firewalls: one in the cloud or network, and **ufw** on the server itself.

```bash
sudo ufw status verbose
sudo ufw app list
sudo ufw app info "Apache"
```

| Profile | Opens |
|---|---|
| `Apache` | 80 |
| `Apache Secure` | 443 |
| `Apache Full` | 80 and 443 |
| `OpenSSH` | 22 |

**Allow ssh first, or you lock yourself out:**

```bash
sudo ufw allow OpenSSH
sudo ufw enable
sudo ufw status numbered
```

Now your laptop browser **times out** on `http://[vm-ip]/` (curl on the VM still works). Open port 80:

```bash
sudo ufw allow "Apache"
sudo ufw status numbered
```

The laptop works again.

| Command | Does |
|---|---|
| `ufw allow 8090/tcp` | open one port |
| `ufw deny from 10.0.0.203` | block one address |
| `ufw limit OpenSSH` | slow down password guessing |
| `ufw status numbered` · `ufw delete 3` | list rules · remove rule 3 |
| `ufw disable` | turn the firewall off (lab only) |

For the rest of the handout, leave ufw **enabled** with OpenSSH and Apache allowed, or disable it:

```bash
sudo ufw disable
```

---

## Exercises

1. Stop Apache and run the three checks. Which check fails first?
2. Show only the status code of `http://localhost/` in one command.
3. Disable Apache at boot, then prove it is still running now.
4. Why is `apache2ctl configtest && systemctl reload apache2` safer than two separate commands?
5. With ufw enabled and only OpenSSH allowed, what does the laptop browser show: refused or timed out? Why?

## Answers

1. Check 1: `systemctl status` shows `inactive (dead)`; then `ss` shows no `:80`, and curl says `Failed to connect to localhost port 80 … Couldn't connect to server`.
2. `curl -s -o /dev/null -w "%{http_code}\n" http://localhost/`.
3. `sudo systemctl disable apache2 ; systemctl is-active apache2` → `active`.
4. The reload runs only if the test passed, so a typo never reaches a reload.
5. Timed out: ufw silently drops the packets, so nothing answers (refused would mean the machine answered "nobody here").
