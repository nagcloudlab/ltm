# 03 · Server blocks: websites in Nginx

**Time:** 40 min

**You will learn:** the shop site line by line, `listen` with addresses, how Nginx picks a server block (`server_name`, `default_server`), a second site on the same port by name, a third site on its own port, testing with `/etc/hosts`, and enabling/disabling sites.

---

## 03.1 · The shop site, line by line

```bash
cat /etc/nginx/sites-available/shop
```

| Line | Means | Apache |
|---|---|---|
| `server { … }` | one website | `<VirtualHost>` |
| `listen 8081 default_server;` | port, and "answer here when no name matches" | `Listen` + `<VirtualHost *:8081>` |
| `server_name shop.example.com;` | the site's names | `ServerName` |
| `root /var/www/shop;` | page folder | `DocumentRoot` |
| `index index.html;` | start file for folder URLs | `DirectoryIndex` |
| `location / { try_files $uri $uri/ =404; }` | file? folder? else 404 (topic 04) | (automatic in Apache) |
| `access_log` / `error_log` | this site's own logs | `CustomLog` / `ErrorLog` |

## 03.2 · listen: which address, which port

| Line | Listens on | From this server | From other machines |
|---|---|---|---|
| `listen 8081;` | every IPv4 address (0.0.0.0) | ✓ | ✓ |
| `listen 127.0.0.1:8081;` | loopback only | ✓ | ✕ refused |
| `listen [::]:8081;` | every IPv6 address | ✓ | ✓ |
| `listen 8081 default_server;` | as first line + fallback for this port | | |

Try the loopback-only version:

```bash
sudo cp /etc/nginx/sites-available/shop /etc/nginx/sites-available/shop.bak
sudo sed -i 's/listen 8081 default_server;/listen 127.0.0.1:8081 default_server;/' /etc/nginx/sites-available/shop
sudo nginx -t && sudo systemctl reload nginx
sudo ss -lntp | grep nginx
sudo tail -n 2 /var/log/nginx/error.log
```

- `ss` still shows `0.0.0.0:8081`: the reload **did not** move the port.
- The error log says why. Sample line:

```text
2026/11/12 20:34:35 [emerg] 2540#2540: bind() to 127.0.0.1:8081 failed (98: Address already in use)
```

- During a reload the old `0.0.0.0:8081` socket is still open, so the new `127.0.0.1:8081` cannot open. Nginx keeps the old config.
- Rule: **a change of listen address on the same port needs `restart`**.

```bash
sudo systemctl restart nginx
sudo ss -lntp | grep nginx
curl -I http://localhost:8081/
```

`ss` now shows `127.0.0.1:8081`. Ask your neighbour to run `curl -I http://[your-vm-ip]:8081/`: **refused**. Running and listening, yet unreachable: the Linux topic 10 lesson. Undo (restart again, same reason):

```bash
sudo cp /etc/nginx/sites-available/shop.bak /etc/nginx/sites-available/shop
sudo nginx -t && sudo systemctl restart nginx
sudo ss -lntp | grep nginx
```

> After every `listen` change: `ss -lntp | grep nginx` to prove what is really open.

## 03.3 · A second website on the same port, by name

```bash
sudo mkdir -p /var/www/blog
echo "<h1>Blog</h1><p>served by Nginx</p>" | sudo tee /var/www/blog/index.html
sudo vi /etc/nginx/sites-available/blog
```

```nginx
server {
    listen 8081;
    server_name blog.example.com www.blog.example.com;
    root /var/www/blog;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    access_log /var/log/nginx/blog-access.log;
    error_log  /var/log/nginx/blog-error.log;
}
```

```bash
sudo ln -s /etc/nginx/sites-available/blog /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
curl -H "Host: blog.example.com" http://localhost:8081/
curl -H "Host: www.blog.example.com" http://localhost:8081/
curl -H "Host: shop.example.com" http://localhost:8081/
curl -H "Host: unknown.example.com" http://localhost:8081/
```

## 03.4 · How Nginx picks the server block

```text
request on port 8081 with Host: X
   │
   ├─ a server_name equals X exactly?                  → that block
   ├─ a wildcard name matches (*.example.com)?         → that block
   ├─ a regex name matches (~^blog\d+\.example\.com$)? → that block
   └─ nothing matches                                  → the default_server for 8081
                                                         (or the first block loaded, if none is marked)
```

| Host sent | Answered by |
|---|---|
| `blog.example.com`, `www.blog.example.com` | blog |
| `shop.example.com` | shop |
| anything else | shop (`default_server`) |

**Catch-all that refuses unknown names** (a good production habit):

```nginx
server {
    listen 8081 default_server;
    server_name _;
    return 444;
}
```

(`444` is Nginx-only: close the connection without any answer. Do not add this now; it would replace shop as the default.)

## 03.5 · Test with real names: /etc/hosts

```bash
grep -q "blog.example.com" /etc/hosts || echo "127.0.0.1 shop.example.com blog.example.com www.blog.example.com" | sudo tee -a /etc/hosts
curl http://blog.example.com:8081/
curl -v http://blog.example.com:8081/ 2>&1 | grep "> Host"
```

The Host header now includes the port (`blog.example.com:8081`); Nginx ignores the port part when matching names.

## 03.6 · Which sites are loaded? (Nginx has no -S)

```bash
ls -l /etc/nginx/sites-enabled/
sudo nginx -T | grep -E "^\s*(listen|server_name)"
```

## 03.7 · A website on its own port

```bash
sudo mkdir -p /var/www/stats
echo "<h1>Stats on 8082</h1>" | sudo tee /var/www/stats/index.html
sudo vi /etc/nginx/sites-available/stats
```

```nginx
server {
    listen 8082;
    root /var/www/stats;
    index index.html;
    access_log /var/log/nginx/stats-access.log;
}
```

```bash
sudo ln -s /etc/nginx/sites-available/stats /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo ss -lntp | grep nginx
curl http://localhost:8082/
```

Unlike Apache, there is **no separate Listen file**: the `listen` line in the server block opens the port.

## 03.8 · Disable and enable a site

```bash
sudo rm /etc/nginx/sites-enabled/stats
sudo nginx -t && sudo systemctl reload nginx
curl -I http://localhost:8082/
sudo ln -s /etc/nginx/sites-available/stats /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

| Mistake | What happens |
|---|---|
| `cp` instead of `ln -s` into sites-enabled | works, but later edits in sites-available are **ignored** |
| link with a relative path from the wrong folder | broken link; `nginx -t` reports "No such file" |
| a backup file `shop.bak` inside sites-enabled | it is loaded too (`include sites-enabled/*`): duplicate sites |

> Keep backups in `sites-available` or elsewhere, **never** in `sites-enabled`.

---

## Exercises

1. Add `blog` as a short name (no domain) to the blog site and prove it with curl.
2. Make `blog` the default site for 8081 instead of shop. What changes for unknown names?
3. Bind `stats` to loopback only. Prove the neighbour is refused.
4. Someone copied `shop` to `sites-enabled/shop.old`. What does `nginx -t` say?
5. How do you list every port Nginx is configured to listen on, without `ss`?

## Answers

1. `server_name blog.example.com www.blog.example.com blog;` → `curl -H "Host: blog" http://localhost:8081/`.
2. Move `default_server` from shop's listen line to blog's; unknown names now get the blog page.
3. `listen 127.0.0.1:8082;`, `nginx -t`, **restart** (a reload logs `bind() … (98: Address already in use)`); `ss` shows `127.0.0.1:8082`; neighbour's `curl` → refused.
4. The test fails: `[emerg] a duplicate default server for 0.0.0.0:8081 in /etc/nginx/sites-enabled/shop.old`. Without `default_server` it would only warn `conflicting server name … ignored`. Remove the copy.
5. `sudo nginx -T | grep -E "^\s*listen"`.
