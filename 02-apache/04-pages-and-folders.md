# 04 · Pages and folders: DocumentRoot, access rules, ownership

**Time:** 45 min

**You will learn:** how a URL becomes a file, your first pages, 404, static vs dynamic, who should own web files, how Apache locks and opens folders (`<Directory>`, `Require`), the first 403, folder listings, `Alias`.

---

## 04.1 · The URL path becomes a file path

```
http://localhost/hello.html   →  DocumentRoot /var/www/html  +  /hello.html
http://localhost/             →  /var/www/html/ + index.html (the start file)
http://localhost/missing.html →  no such file  →  404
```

```bash
grep -n DocumentRoot /etc/apache2/sites-available/000-default.conf
cat /etc/apache2/mods-enabled/dir.conf
```

- `DirectoryIndex index.html index.cgi index.pl index.php index.xhtml index.htm`: the start files tried, in order, when the URL is a folder.

## 04.2 · Publish your first pages

```bash
echo "Hello from $(whoami)" | sudo tee /var/www/html/hello.html
curl http://localhost/hello.html
curl -I http://localhost/hello.html
curl -I http://localhost/nothing.html
```

`sudo tee` writes into a file that only root may create (`sudo echo … > file` does **not** work: the `>` runs as you).

A small real page with a stylesheet:

```bash
sudo mkdir -p /var/www/html/shop
sudo tee /var/www/html/shop/index.html <<'EOF'
<!doctype html>
<html><head><title>PayBank Shop</title><link rel="stylesheet" href="style.css"></head>
<body><h1>PayBank Shop</h1><p>Served by Apache from /var/www/html/shop</p></body></html>
EOF
echo "body { font-family: sans-serif; background: #f7f5f0; }" | sudo tee /var/www/html/shop/style.css
curl -I http://localhost/shop/
curl -I http://localhost/shop/style.css
```

Open `http://[vm-ip]/shop/` on your laptop: the browser makes **two** requests (page, then CSS). Check:

```bash
sudo tail -n 3 /var/log/apache2/access.log
```

## 04.3 · Content-Type comes from the extension

```bash
curl -sI http://localhost/shop/index.html | grep -i content-type
curl -sI http://localhost/shop/style.css  | grep -i content-type
grep -E "^text/css|^text/html|^image/png" /etc/mime.types
```

Apache picks `Content-Type` from `/etc/mime.types`. A page that **downloads instead of opening**, or shows as raw text, usually has the wrong extension or type.

## 04.4 · Static vs dynamic

| Static | Dynamic |
|---|---|
| a file on disk: `.html`, `.css`, `.png` | built per request by a program |
| same bytes for every visitor | different per visitor (your balance) |
| Apache sends it itself, very fast | needs an application server (Tomcat, later) |

## 04.5 · Who should own web files?

```bash
ls -l /var/www/html/shop
ls -ld /var/www/html/shop
sudo -u www-data cat /var/www/html/shop/index.html
```

| Do | Don't |
|---|---|
| owner `root`, files **644**, folders **755** | `chmod 777`: anyone can change your site |
| www-data only **reads** | `chown www-data` on pages: a tricked worker can rewrite every page |

Both "don't"s make a 403 go away and open a security hole.

## 04.6 · Apache locks every folder, then opens a few

```bash
grep -n -A4 "<Directory" /etc/apache2/apache2.conf
```

```
/            ✕ Require all denied      the whole disk: locked
/usr/share   ✓ Require all granted
/var/www     ✓ Require all granted     websites live here
/srv, /home  ✕ (inherit /)             locked
```

Safe by design: a wrong DocumentRoot cannot hand out `/etc/shadow`.

## 04.7 · A `<Directory>` block, line by line

```apache
<Directory /var/www/>
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
```

| Line | Means |
|---|---|
| `<Directory /var/www/>` | this folder and everything below |
| `Options Indexes` | show a file listing when there is no index file |
| `Options FollowSymLinks` | follow symbolic links |
| `AllowOverride None` | ignore `.htaccess` files (topic 07) |
| `Require all granted` | who may read: everyone |

## 04.8 · Require: who may come in

| Line | Who | Use |
|---|---|---|
| `Require all granted` | everyone | public site |
| `Require all denied` | no one | secret folders |
| `Require local` | only this server | status pages |
| `Require ip 10.0.0.0/24` | one network | office only |
| `Require valid-user` | anyone who logs in | topic 07 |

Everyone refused gets **403 Forbidden**: "it exists, but you may not have it".

### Lock a folder, read the log, unlock it

```bash
sudo mkdir -p /var/www/html/private
echo "secret" | sudo tee /var/www/html/private/index.html
sudo cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/000-default.conf.bak
sudo vi /etc/apache2/sites-available/000-default.conf
```

Inside `<VirtualHost *:80>` add:

```apache
    <Directory /var/www/html/private>
        Require all denied
    </Directory>
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -I http://localhost/private/
sudo tail -n 2 /var/log/apache2/error.log
```

The error log says `AH01630: client denied by server configuration`. Change `denied` to `local`, reload, curl again: 200 from the server itself, still 403 from your laptop.

## 04.9 · A site in a new folder gets 403

```bash
sudo mkdir -p /srv/docs
echo "docs home" | sudo tee /srv/docs/index.html
```

Map a URL to it with **Alias** (inside the VirtualHost):

```apache
    Alias /docs /srv/docs
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -I http://localhost/docs/
sudo tail -n 1 /var/log/apache2/error.log
```

403 + `AH01630`: `/srv` is still locked by `<Directory />`. Open **just that folder**:

```apache
    <Directory /srv/docs>
        Require all granted
    </Directory>
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl http://localhost/docs/
```

> Never "fix" this by changing `<Directory />` to granted: Apache could then serve any readable file on the disk.

## 04.10 · No index.html? A file listing

```bash
sudo mkdir -p /var/www/html/files
sudo touch /var/www/html/files/backup.zip /var/www/html/files/db-dump.sql
curl -s http://localhost/files/ | grep -o 'href="[^"]*"'
```

`Options Indexes` + no index file = **anyone can see and download every file**: a classic leak. Turn it off in the `/var/www/` Directory block of `apache2.conf`:

```apache
    Options -Indexes +FollowSymLinks
```

```bash
sudo cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf.bak
sudo vi /etc/apache2/apache2.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -I http://localhost/files/
```

Now **403**: a safe "no". The error log says why:

```bash
sudo tail -n 1 /var/log/apache2/error.log
```

Sample line:

```text
[Thu Nov 12 20:55:40.036732 2026] [autoindex:error] [pid 4121:tid 281473673457952] [client 127.0.0.1:33328] AH01276: Cannot serve directory /var/www/html/files/: No matching DirectoryIndex (index.html,index.cgi,index.pl,index.php,index.xhtml,index.htm) found, and server-generated directory index forbidden by Options directive
```

- `AH01276` = a folder, no start file, and listings are off.

## 04.11 · The other 403: Linux permissions

```bash
sudo chmod 700 /var/www/html/shop
curl -I http://localhost/shop/
sudo tail -n 1 /var/log/apache2/error.log
sudo chmod 755 /var/www/html/shop
```

| Error log says | Cause | Fix |
|---|---|---|
| `AH01630: client denied by server configuration` | a `Require` rule | the `<Directory>` / Require line |
| `(13)Permission denied: … AH00035: access to /shop/index.htm denied (filesystem path …) because search permissions are missing on a component of the path` | www-data can't enter a folder (no `x`) | `chmod 755` on the folder **and every parent** |
| `(13)Permission denied: … AH00132: file permissions deny server access: /var/www/html/hello.html` | www-data can't read the file | `chmod 644` |

- `(13)` is the Linux error number 13, "permission denied", the same number you saw in the Linux handout.
- `AH00035` names `index.htm` (the last start file Apache tried), not `index.html`: it could not even look inside the folder.

Check every parent folder at once:

```bash
namei -l /var/www/html/shop/index.html
```

---

## Exercises

1. Which file is served for `http://localhost/shop/`? Why that one?
2. Create `/var/www/html/notes.txt`. Which Content-Type does Apache send?
3. Make `/var/www/html/private` reachable only from the office network `10.0.0.0/24`.
4. `curl /files/` shows a listing again after someone edited apache2.conf. What do you look for?
5. A 403 shows `AH00035 … search permissions are missing`. Which command shows the folder at fault?

## Answers

1. `index.html`: the URL is a folder, so Apache tries the `DirectoryIndex` names in order.
2. `curl -sI http://localhost/notes.txt | grep -i content-type` → `text/plain`.
3. `Require ip 10.0.0.0/24` in its Directory block, then configtest and reload.
4. `grep -n "Options" /etc/apache2/apache2.conf` for `Indexes` without the minus sign.
5. `namei -l <full path of the file>`: the folder whose mode lacks `x` for others.
