# 10 · Troubleshooting: break it, read it, fix it

**Time:** 45 min

**You will learn:** a fixed method, `curl -v`, and how to diagnose the common failures: Apache won't start, the port is taken, a config typo, two kinds of 403, 404, 500, the wrong website, and "works on the server, times out from the laptop". Every case: **break it yourself**, read the evidence, fix it.

---

## 10.1 · The method: read what curl says

| curl says | Means | Look at |
|---|---|---|
| `Could not resolve host` | the name is unknown | `/etc/hosts`, DNS |
| `Failed to connect … Couldn't connect to server` (refused) | nothing listens on the port | `systemctl status`, `ss -lntp` |
| times out | blocked on the way | `ufw status`, network team |
| `404 Not Found` | no file at that path | DocumentRoot, `ls` the folder |
| `403 Forbidden` | not allowed | error log: Require or permissions |
| `500 Internal Server Error` | server failed on the request | error log |
| `200`, but the wrong page | wrong website chosen | `apache2ctl -S`, Host vs ServerName |

The first three: Apache never saw the request, so its logs are empty. The rest: Apache answered, so **its logs know why**.

## 10.2 · curl -v: see every step

```bash
curl -v http://localhost/hello.html
```

| Lines starting with | Mean |
|---|---|
| `*` | curl describing the connection (DNS, TCP) |
| `>` | what you **sent** |
| `<` | what came **back** |
| no prefix | the body |

If curl stops after the `*` lines with an error, the problem is network or port. If a `< HTTP/1.1` line appears, Apache answered.

## 10.3 · Case 1: Apache won't start (three places to look)

**Break it:**

```bash
sudo cp /etc/apache2/sites-available/portal.conf /etc/apache2/sites-available/portal.conf.bak
sudo sed -i 's/DocumentRoot/DocumentRot/' /etc/apache2/sites-available/portal.conf
sudo systemctl restart apache2
```

**Diagnose:**

```bash
systemctl status apache2 --no-pager
journalctl -u apache2 -n 20 --no-pager
sudo apache2ctl configtest
```

| Step | Command | Shows |
|---|---|---|
| 1 did it fail? | `systemctl status` | `Active: failed` + last lines |
| 2 why? | `journalctl -u apache2` | full start-up messages |
| 3 config broken? | `apache2ctl configtest` | `AH00526: Syntax error on line 4 of /etc/apache2/sites-enabled/portal.conf: Invalid command 'DocumentRot'` |

- The path says `sites-enabled`: Apache reads the link. Edit the real file in `sites-available`.

**Fix:**

```bash
sudo cp /etc/apache2/sites-available/portal.conf.bak /etc/apache2/sites-available/portal.conf
sudo apache2ctl configtest && sudo systemctl start apache2
curl -I http://localhost/
```

The whole website was down because of one letter and a **restart without configtest**.

## 10.4 · Case 2: the port is already taken

**Break it:** stop Apache and let another program take port 80.

```bash
sudo systemctl stop apache2
sudo python3 -m http.server 80 --directory /tmp > /dev/null 2>&1 &
sleep 2
sudo systemctl start apache2
```

**Diagnose:**

```bash
journalctl -u apache2 -n 10 --no-pager | grep -i -E "address|bind"
sudo ss -lntp 'sport = :80'
```

`(98)Address already in use: AH00072: make_sock: could not bind to address 0.0.0.0:80` and `ss` names the owner: `python3`.

**Fix:** decide who owns port 80, then move or stop the other program.

```bash
sudo fuser -v 80/tcp
sudo fuser -k 80/tcp
sudo systemctl start apache2
sudo ss -lntp | grep ':80 '
```

- `fuser -v 80/tcp` shows who holds the port; `fuser -k 80/tcp` stops it.
- Use `-k` only after you know what the program is.

> Never kill a process you don't recognise. Find out what it is first (`ps -fp PID`). You will meet this for real when you install Nginx.

## 10.5 · Case 3: 403 from a Require rule

**Break it:**

```bash
curl -I http://localhost/private/
sudo tail -n 1 /var/log/apache2/error.log
```

(The `private` folder is denied since topic 04.) Error log: **`AH01630: client denied by server configuration`**.

**Fix:** change the `Require` line in that `<Directory>` block (or remove the block), configtest, reload.

## 10.6 · Case 4: 403 from Linux permissions

**Break it:**

```bash
sudo chmod 700 /var/www/portal
curl -I -H "Host: portal.example.com" http://localhost/
sudo tail -n 1 /var/log/apache2/portal-error.log
```

Sample line (portal-error.log):

```text
[Thu Nov 12 22:38:35.572079 2026] [core:error] [pid 6749:tid 281473667428640] (13)Permission denied: [client 127.0.0.1:47262] AH00035: access to /index.htm denied (filesystem path '/var/www/portal/index.htm') because search permissions are missing on a component of the path
```

**Diagnose:**

```bash
namei -l /var/www/portal/index.html
sudo -u www-data cat /var/www/portal/index.html
```

**Fix:**

```bash
sudo chmod 755 /var/www/portal
curl -I -H "Host: portal.example.com" http://localhost/
```

| Error log | Cause | Fix |
|---|---|---|
| `AH01630` | a Require rule | the `<Directory>` block |
| `AH00035 … search permissions` | a folder without `x` for www-data | `chmod 755` folder (and parents) |
| `AH00132: file permissions deny server access` | file not readable | `chmod 644` file |

## 10.7 · Case 5: 404, but "the file is there"

**Break it:**

```bash
sudo sed -i 's#DocumentRoot /var/www/portal$#DocumentRoot /var/www/portal2#' /etc/apache2/sites-available/portal.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
curl -I -H "Host: portal.example.com" http://localhost/
```

- configtest **warns**: `AH00112: Warning: DocumentRoot [/var/www/portal2] does not exist`, then still says `Syntax OK`. Read warnings, not just the last line.
- The 404 writes **no** line in portal-error.log: a missing file is not an error to Apache. Only the access log shows the 404.

**Diagnose:**

```bash
sudo apache2ctl -S | grep portal
grep -n DocumentRoot /etc/apache2/sites-available/portal.conf
diff /etc/apache2/sites-available/portal.conf.bak /etc/apache2/sites-available/portal.conf
```

**Fix:** restore the file from `.bak`, configtest, reload. `diff` against the last backup is the fastest way to answer "what changed?".

## 10.8 · Case 6: 500 from a broken .htaccess

Done in topic 07.6. Remember: **configtest cannot see .htaccess**; the error log names the file and the bad word.

## 10.9 · Case 7: the wrong website answers

**Break it:**

```bash
curl -s -H "Host: PORTAL.example.com" http://localhost/ | head -n 3
curl -s -H "Host: portal" http://localhost/ | head -n 3
```

(Host names are case-insensitive, so the first still works. A name that matches no `ServerName`/`ServerAlias` gets the **default** site.)

**Diagnose:**

```bash
sudo apache2ctl -S
```

**Fix:** add the missing name as a `ServerAlias`, configtest, reload.

## 10.10 · Case 8: works on the server, times out from the laptop

**Break it:**

```bash
sudo ufw allow OpenSSH
sudo ufw enable
curl -I http://localhost/
```

On the VM: 200. From the laptop browser: spins, then **times out**.

| Symptom | Means |
|---|---|
| curl on the server works | Apache is fine |
| laptop times out (not refused) | something in between drops the packets |

**Diagnose:** `sudo ufw status`. **Fix:** `sudo ufw allow "Apache"`. If ufw is not the cause, it is the cloud/network firewall: escalate to the network team with the evidence.

```bash
sudo ufw disable
```

## 10.11 · Case 9: slow pages

```bash
uptime
free -h
curl -s "http://localhost/server-status?auto" | grep -E "Busy|Idle"
sudo grep -i MaxRequestWorkers /var/log/apache2/error.log
sudo awk '{print $NF/1000000, $7}' /var/log/apache2/access.log | sort -n | tail -n 5
```

| Finding | Points to |
|---|---|
| high load, low CPU idle | the server is overloaded |
| `available` memory near zero | memory: swap, OOM |
| BusyWorkers near 150, MaxRequestWorkers warning | out of workers (topic 09) |
| only some URLs slow (`%D`) | the application or database behind those URLs |

## 10.12 · Troubleshooting checklist

1. What exactly does `curl -I` (or `-v`) say?
2. Is Apache running? (`systemctl status`)
3. Is the port open, and by whom? (`ss -lntp`)
4. Does configtest pass, and are there warnings?
5. Which site answers? (`apache2ctl -S`)
6. What do **both** logs say at that time? (`tail`, `grep` by time)
7. What changed? (`diff` with `.bak`, `ls -lt`, `grep apache2 /var/log/apt/history.log`)
8. Fix one thing, test, verify, write it down.

---

## Exercises

Break each one yourself, then diagnose **without** looking at the case above. Write the evidence line that proved the cause.

1. Remove `Listen 80` from ports.conf and restart. What do curl and ss say?
2. Disable the portal site and reload. What does `portal.example.com` show now?
3. `sudo chmod 600 /var/www/html/hello.html`. Which code, which error-log line?
4. Put an unknown directive in a site file and **reload** (not restart). Is the site down?
5. Set `DocumentRoot /var/www/portal` in **both** portal.conf and admin.conf. What does `apache2ctl -S` show, and is it an error?

## Answers

1. Apache **fails to start**: `journalctl -u apache2` shows `no listening sockets available, shutting down`; curl → `Couldn't connect to server`, `ss` shows no `:80`. Put the line back and start it.
2. The default page: `apache2ctl -S` no longer lists portal.
3. 403; error log: `(13)Permission denied: … AH00132: file permissions deny server access: /var/www/html/hello.html`. Fix `chmod 644`.
4. No: the reload fails (`Job for apache2.service failed.`) and the old config keeps running; `systemctl status` still says `active (running)`, and `journalctl -u apache2` shows `Reload failed for apache2.service` with the bad line. A restart now would bring the site down.
5. Both sites show the same content; `-S` lists both names normally. Not an error to Apache, only a mistake for users: always check each DocumentRoot.
