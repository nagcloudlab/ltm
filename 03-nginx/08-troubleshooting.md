# 08 · Troubleshooting Nginx: break it, read it, fix it

**Time:** 45 min

**You will learn:** a fixed method, and nine failures you cause yourself: port taken, missing `;`, unknown directive, a passing test with warnings, 404 from `root`/`alias`, 403 from a folder with no index, 403 from permissions, 405/413, and the wrong website.

---

## 08.1 · The method

| Step | Command |
|---|---|
| 1 what does the client get? | `curl -sv http://localhost:8081/path` |
| 2 running? | `systemctl status nginx` |
| 3 listening, on which address? | `sudo ss -lntp \| grep nginx` |
| 4 config valid? warnings? | `sudo nginx -t` |
| 5 which block answers? | `sudo nginx -T \| grep -E "listen\|server_name\|location"` |
| 6 what do the logs say at that time? | `sudo tail -n 20 /var/log/nginx/*error.log` |
| 7 what changed? | `diff` with the `.bak`, `ls -lt /etc/nginx/sites-enabled/` |

Nginx's error log usually names the **exact path it tried** and the **errno**: read it first.

## 08.2 · Case 1: port already in use

**Break it:**

```bash
sudo cp /etc/nginx/sites-available/stats /etc/nginx/sites-available/stats.bak
sudo sed -i 's/listen 8082;/listen 80;/' /etc/nginx/sites-available/stats
sudo nginx -t
sudo systemctl reload nginx
sudo tail -n 2 /var/log/nginx/error.log
curl -I http://localhost:8081/
sudo systemctl restart nginx
```

**Diagnose:**

```bash
systemctl status nginx --no-pager
journalctl -u nginx -n 5 --no-pager
sudo ss -lntp 'sport = :80'
```

- `nginx -t` passes: the **syntax** is fine.
- `reload`: the error log shows `bind() to 0.0.0.0:80 failed (98: Address already in use)`, but the old config keeps running (curl on 8081 still works).
- `restart`: `Job for nginx.service failed`. Nginx stopped and cannot start again. **All** Nginx sites are now down, not just stats.
- `ss` shows apache2 on port 80.

**Fix:**

```bash
sudo cp /etc/nginx/sites-available/stats.bak /etc/nginx/sites-available/stats
sudo nginx -t && sudo systemctl start nginx
```

> `nginx -t` cannot know another program owns a port. A `restart` after a `listen` change is risky: prefer `reload` (a failed reload keeps the old config running).

## 08.3 · Case 2: a missing semicolon

**Break it:**

```bash
sudo cp /etc/nginx/sites-available/shop /etc/nginx/sites-available/shop.bak
sudo sed -i '0,/root \/var\/www\/shop;/s//root \/var\/www\/shop/' /etc/nginx/sites-available/shop
sudo nginx -t
```

Sample line:

```text
2026/11/13 00:38:47 [emerg] 4816#4816: invalid number of arguments in "root" directive in /etc/nginx/sites-enabled/shop:5
```

- Nginx joined `root /var/www/shop` with the next line `index index.html;`, so `root` got too many words.
- The same mistake gives different messages depending on the next line:

| Missing `;` after | `nginx -t` says |
|---|---|
| `root /var/www/shop` (next line is a directive) | `invalid number of arguments in "root" directive` |
| `index index.html` (next line is empty) | `directive "index" is not terminated by ";"` |
| the last line before `}` | `unexpected "}"` |

- The line number can point **after** the real mistake: look one line up.

```bash
sudo cp /etc/nginx/sites-available/shop.bak /etc/nginx/sites-available/shop
sudo nginx -t
```

## 08.4 · Case 3: unknown directive or wrong place

**Break it:**

```bash
sudo sed -i 's/server_name shop.example.com;/server_name shop.example.com;\n    servr_tokens off;/' /etc/nginx/sites-available/shop
sudo nginx -t
```

| Message | Means |
|---|---|
| `unknown directive "servr_tokens"` | typo, or the module is not loaded |
| `"listen" directive is not allowed here` | right word, wrong block (context) |
| `unexpected "}"` | a block closed too early or a `{` missing |
| `unexpected end of file, expecting "}"` | a block never closed |

```bash
sudo cp /etc/nginx/sites-available/shop.bak /etc/nginx/sites-available/shop
sudo nginx -t
```

## 08.5 · Case 4: test passes, but read the warnings

**Break it:** a forgotten copy in sites-enabled.

```bash
sudo cp /etc/nginx/sites-available/blog /etc/nginx/sites-enabled/blog-copy
sudo nginx -t
```

`[warn] conflicting server name "blog.example.com" on 0.0.0.0:8081, ignored` and then `test is successful`. One of the two blocks is **silently ignored**: edits in it never take effect.

```bash
sudo rm /etc/nginx/sites-enabled/blog-copy
sudo nginx -t
```

> "test is successful" means it will load, not that it does what you meant. Read every `[warn]`.

## 08.6 · Case 5: 404 with root vs alias

**Break it:**

```bash
sudo sed -i 's#alias /srv/manuals/;#root /srv/manuals/;#' /etc/nginx/sites-available/shop
sudo nginx -t && sudo systemctl reload nginx
curl -I http://localhost:8081/manuals/
sudo tail -n 1 /var/log/nginx/shop-error.log
```

`"/srv/manuals/manuals/index.html" is not found (2: No such file or directory)`: the path proves `root` added the location part. Put `alias` back and reload.

## 08.7 · Case 6: 403 from a folder with no index

```bash
sudo mkdir -p /var/www/shop/reports
curl -I http://localhost:8081/reports/
sudo tail -n 1 /var/log/nginx/shop-error.log
```

`directory index of "/var/www/shop/reports/" is forbidden`. Fix: add an `index.html`, or `autoindex on;` if a listing is really wanted.

## 08.8 · Case 7: 403 from permissions

**Break it:**

```bash
sudo chmod 600 /var/www/shop/style.css
curl -I http://localhost:8081/style.css
sudo tail -n 1 /var/log/nginx/shop-error.log
namei -l /var/www/shop/style.css
sudo -u www-data cat /var/www/shop/style.css
sudo chmod 644 /var/www/shop/style.css
```

`open() "/var/www/shop/style.css" failed (13: Permission denied)`.

| Error log | Cause | Fix |
|---|---|---|
| `(2: No such file or directory)` | wrong path / missing file | root/alias, file name |
| `(13: Permission denied)` on a file | www-data can't read the file (403) | `chmod 644` files |
| `[crit] … "/var/www/shop/docs/" failed (13: Permission denied)` | www-data can't enter a folder: try_files gives **404** | `chmod 755` folders |
| `directory index … is forbidden` | folder without index | index file or autoindex |
| `access forbidden by rule` | allow/deny | the location rules |

## 08.9 · Case 8: 405 and 413 on uploads

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST -d "a=1" http://localhost:8081/
head -c 30000000 /dev/zero > ~/big30.bin
curl -s -o /dev/null -w "%{http_code}\n" -X POST --data-binary @$HOME/big30.bin http://localhost:8081/
rm ~/big30.bin
```

- With the `limit_except GET` rule from topic 05, the small POST gets **403**; without that rule it gets **405**.

| Code | Means | Look at |
|---|---|---|
| 405 | POST/PUT/DELETE to a static location | the request should go to an application (reverse proxy) |
| 403 | the method is blocked by `limit_except` | the location rules |
| 413 | body larger than `client_max_body_size` | raise it in that server/location |

## 08.10 · Case 9: the wrong website answers

```bash
curl -s -H "Host: blog" http://localhost:8081/ | head -n 1
curl -s http://[vm-ip]:8081/ | head -n 1
sudo nginx -T | grep -E "listen|server_name"
```

A name that matches no `server_name` goes to the `default_server` of that port (shop). Fix by adding the name to the right `server_name` list, or by adding a catch-all `server_name _; return 444;` default block.

## 08.11 · Nginx troubleshooting checklist

1. curl result: refused / timed out / status code?
2. `systemctl status nginx` and `journalctl -u nginx`
3. `ss -lntp`: right port, right **address** (0.0.0.0 vs 127.0.0.1)?
4. `nginx -t`: errors **and warnings**
5. `nginx -T`: which server and location match this request?
6. error log: path tried + errno
7. `diff` with the backup, `ls -l sites-enabled` for stray copies
8. fix one thing → `nginx -t && systemctl reload nginx` → curl → note it

---

## Exercises

Break each yourself; write the one evidence line that proved the cause.

1. Remove the closing `}` of the shop server block.
2. Point shop's `root` at `/var/www/shopp`.
3. Change the stats site to `listen 127.0.0.1:8082;`, reload, and test from your neighbour. Then restart and test again.
4. Put `client_max_body_size 1k;` in shop and POST 2 KB.
5. Leave a file `sites-enabled/shop.save` (a copy of shop) and run `nginx -t`.

## Answers

1. `nginx -t`: `unexpected end of file, expecting "}" in /etc/nginx/sites-enabled/shop:…`.
2. curl → 404 for every page. `/` writes only `open() "/var/www/shopp/404.html" failed (2: No such file or directory)` (try_files is quiet; the custom error page is missing too). `/style.css` writes `open() "/var/www/shopp/style.css" failed (2: No such file or directory)`: the path shows the typo.
3. After the reload `ss` still shows `0.0.0.0:8082` and the error log has `bind() to 127.0.0.1:8082 failed (98: Address already in use)`; after `restart`, `ss` shows `127.0.0.1:8082` and the neighbour gets `Connection refused`.
4. `413`; error log `client intended to send too large body`.
5. `[emerg] a duplicate default server for 0.0.0.0:8081` (both copies have `default_server`): test fails.
