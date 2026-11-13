# 05 · Virtual hosts: many websites on one server

**Time:** 45 min

**You will learn:** the default site, name-based virtual hosts, `a2ensite`, the Host header, `ServerAlias`, testing with `/etc/hosts`, reading `apache2ctl -S`, the fallback site, and port-based virtual hosts.

---

## 05.1 · The default site that answered you so far

```bash
grep -v -E "^\s*#|^\s*$" /etc/apache2/sites-available/000-default.conf
```

```apache
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html
    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
```

`000-` makes it load **first**, so it is also the **fallback** when no name matches.

## 05.2 · The idea

```
portal.example.com ─┐                            ┌─► /var/www/portal
admin.example.com  ─┼─► one Apache, one IP :80 ──┼─► /var/www/admin
anything else      ─┘   compares Host header     └─► /var/www/html (000-default)
```

Each website is a **virtual host**, with its own folder and its own logs.

## 05.3 · Website 1: portal

```bash
sudo mkdir -p /var/www/portal
sudo tee /var/www/portal/index.html <<'EOF'
<!doctype html><html><head><title>Portal</title></head>
<body><h1>PayBank Portal</h1><p>portal.example.com</p></body></html>
EOF
sudo vi /etc/apache2/sites-available/portal.conf
```

Type:

```apache
<VirtualHost *:80>
    ServerName portal.example.com
    ServerAlias www.portal.example.com
    DocumentRoot /var/www/portal
    ErrorLog ${APACHE_LOG_DIR}/portal-error.log
    CustomLog ${APACHE_LOG_DIR}/portal-access.log combined
</VirtualHost>
```

| Line | Means |
|---|---|
| `<VirtualHost *:80>` | answer on port 80, any address |
| `ServerName` | the website's main name |
| `ServerAlias` | extra names for the same site (one per line, or several on one line) |
| `DocumentRoot` | its page folder |
| `ErrorLog` / `CustomLog` | its **own** logs: much easier troubleshooting |

## 05.4 · Switch it on

```bash
sudo a2ensite portal
ls -l /etc/apache2/sites-enabled/
sudo apache2ctl configtest && sudo systemctl reload apache2
```

| Command | Does |
|---|---|
| `a2ensite portal` | creates the link `sites-enabled/portal.conf → ../sites-available/portal.conf` |
| `a2dissite portal` | removes the link (your file is kept) |
| nothing changes | until you **reload** |

## 05.5 · Test with the Host header

```bash
curl -H "Host: portal.example.com" http://localhost/
curl -H "Host: www.portal.example.com" http://localhost/
curl -H "Host: something-else" http://localhost/
curl http://localhost/
```

| Host sent | Answered by |
|---|---|
| `portal.example.com` | portal (ServerName) |
| `www.portal.example.com` | portal (ServerAlias) |
| anything else / none | **000-default** (loaded first) |

## 05.6 · Website 2: admin

```bash
sudo mkdir -p /var/www/admin
echo "<h1>PayBank Admin</h1>" | sudo tee /var/www/admin/index.html
sudo sed 's/portal/admin/g' /etc/apache2/sites-available/portal.conf | sudo tee /etc/apache2/sites-available/admin.conf
cat /etc/apache2/sites-available/admin.conf
sudo a2ensite admin
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -H "Host: admin.example.com" http://localhost/
```

`sed 's/portal/admin/g'` copies the portal file with every `portal` replaced by `admin`: a quick way to clone a site file. Always `cat` the result.

## 05.7 · Read the website map: apache2ctl -S

```bash
sudo apache2ctl -S
```

| Line | Means |
|---|---|
| `*:80 is a NameVirtualHost` | port 80 is shared by name |
| `default server localhost (…000-default.conf:1)` | who answers when no name matches |
| `port 80 namevhost portal.example.com (…portal.conf:1)` | one line per site, with file and line |
| `alias www.portal.example.com` | its aliases |

"The wrong website answers" → run `apache2ctl -S` first.

## 05.8 · Test with the real name: /etc/hosts

```bash
sudo cp /etc/hosts /etc/hosts.bak
echo "127.0.0.1 portal.example.com admin.example.com" | sudo tee -a /etc/hosts
curl http://portal.example.com/
curl http://admin.example.com/
curl -v http://portal.example.com/ 2>&1 | grep "> Host"
```

curl now sends the right Host header by itself, exactly like a browser.

**From your laptop:** add `[vm-ip] portal.example.com admin.example.com` to the laptop's hosts file (`/etc/hosts` on Mac/Linux, `C:\Windows\System32\drivers\etc\hosts` as Administrator on Windows), then browse `http://portal.example.com/`.

## 05.9 · Choose the fallback yourself

Disable the default site and see who becomes the fallback:

```bash
sudo a2dissite 000-default
sudo apache2ctl configtest && sudo systemctl reload apache2
sudo apache2ctl -S | grep "default server"
curl -H "Host: unknown.example.com" http://localhost/
```

Now `admin` is first alphabetically, so **admin** answers unknown names: a stranger typing your IP sees the admin site. Put the default back:

```bash
sudo a2ensite 000-default
sudo apache2ctl configtest && sudo systemctl reload apache2
```

> Production rule: the fallback (first) site should be a harmless page, never an admin site.

## 05.10 · Port-based virtual hosts

Same server, a site per **port** instead of per name.

```bash
sudo cp /etc/apache2/ports.conf /etc/apache2/ports.conf.bak
echo "Listen 8090" | sudo tee -a /etc/apache2/ports.conf
sudo mkdir -p /var/www/reports
echo "<h1>Reports on port 8090</h1>" | sudo tee /var/www/reports/index.html
sudo vi /etc/apache2/sites-available/reports.conf
```

```apache
<VirtualHost *:8090>
    DocumentRoot /var/www/reports
    ErrorLog ${APACHE_LOG_DIR}/reports-error.log
    CustomLog ${APACHE_LOG_DIR}/reports-access.log combined
</VirtualHost>
```

```bash
sudo a2ensite reports
sudo apache2ctl configtest && sudo systemctl reload apache2
sudo ss -lntp | grep apache2
curl http://localhost:8090/
sudo apache2ctl -S
```

If ufw is enabled: `sudo ufw allow 8090/tcp`, then try `http://[vm-ip]:8090/` from the laptop.

| | Name-based | Port-based |
|---|---|---|
| sites told apart by | Host header | port number |
| needs | DNS or hosts entries | `Listen` + open firewall port |
| users type | `portal.example.com` | `http://server:8090/` |
| used for | public websites | internal tools, admin consoles |

**Break it:** remove the `Listen 8090` line, keep the site, configtest and reload. configtest passes, but curl on 8090 is **refused**: a VirtualHost cannot answer on a door that was never opened. Put the line back.

---

## Exercises

1. Add the name `portal` (no domain) as an alias and prove it works with curl.
2. Disable the admin site without deleting its file, and prove its name now gets the default page.
3. Which file and line define the default server right now?
4. Add a third site on port 9090 with its own folder; then remove it cleanly (site, Listen line, folder).
5. Your colleague added a site but forgot `a2ensite`. What does `apache2ctl -S` show, and what do users see?

## Answers

1. Add `ServerAlias portal` (or append to the existing ServerAlias line), configtest, reload, `curl -H "Host: portal" http://localhost/`.
2. `sudo a2dissite admin && sudo systemctl reload apache2; curl -H "Host: admin.example.com" http://localhost/` → the default page.
3. `sudo apache2ctl -S | grep "default server"`.
4. Same steps as 05.10 with 9090; then `sudo a2dissite site9090; sudo rm /etc/apache2/sites-available/site9090.conf`, delete the `Listen 9090` line, `sudo rm -r` the folder, configtest, reload.
5. The site is missing from the list; its name falls back to the default site.
