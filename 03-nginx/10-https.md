# 10 · HTTPS: a certificate, port 8443, and reading TLS errors

**Time:** 45 min

**You will learn:** what a certificate is, make a self-signed one, serve the shop over HTTPS on **8443**, turn on HTTP/2, allow only TLS 1.2 and 1.3, inspect the handshake with `openssl s_client`, send visitors who use plain HTTP to HTTPS, and read the errors you will meet.

**Before you start:** topics 01–09 done. Apache keeps 80 and 8090; Nginx has 8081 and 8082. HTTPS goes on **8443** (443 is left free for later modules).

---

## 10.1 · HTTPS in plain words

- HTTP sends everything as readable text. Anyone on the network path can read or change it.
- HTTPS = HTTP inside a **TLS** tunnel. Before any page is sent, client and server do a **handshake**:

```text
browser ── "hello, I speak TLS 1.2/1.3" ─────────────►  Nginx
browser ◄─ certificate (name + public key + signature) ─ Nginx
browser:  is the name right? is it signed by someone I trust? not expired?
browser ◄──────── encrypted HTTP from here on ────────►  Nginx
```

- The **certificate** is public. It says "I am shop.example.com" and holds the public key.
- The **private key** stays secret on the server. Whoever has it can pretend to be the site.
- A **self-signed** certificate is signed by itself. Fine for a lab; browsers and curl warn because nobody they trust signed it. Real sites use a certificate from a CA (Let's Encrypt, the company CA).

## 10.2 · Make a key and a self-signed certificate

```bash
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -newkey rsa:2048 -days 365 -keyout /etc/nginx/ssl/shop.key -out /etc/nginx/ssl/shop.crt -subj "/CN=shop.example.com" -addext "subjectAltName=DNS:shop.example.com"
sudo chmod 600 /etc/nginx/ssl/shop.key
ls -l /etc/nginx/ssl/
sudo openssl x509 -in /etc/nginx/ssl/shop.crt -noout -subject -issuer -dates -ext subjectAltName
```

- `-x509` = make a certificate, not a request. `-nodes` = no password on the key (Nginx must read it at start).
- `-days 365` = valid for one year. `notAfter=` is the expiry date: **expired certificates are a classic outage**.
- `subjectAltName` = the names the certificate is valid for. Browsers and curl check **this**, not only `CN`.
- `subject` and `issuer` are the same: that is what "self-signed" means.
- `chmod 600` on the key: only root can read it (the master process is root; workers never need it).

## 10.3 · An HTTPS server block on 8443

```bash
sudo tee /etc/nginx/sites-available/shop-ssl <<'EOF'
server {
    listen 8443 ssl http2;
    server_name shop.example.com;

    ssl_certificate     /etc/nginx/ssl/shop.crt;
    ssl_certificate_key /etc/nginx/ssl/shop.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    root /var/www/shop;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    access_log /var/log/nginx/shop-ssl-access.log;
    error_log  /var/log/nginx/shop-ssl-error.log;
}
EOF
sudo ln -s /etc/nginx/sites-available/shop-ssl /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo ss -lntp | grep 8443
```

| Line | Means |
|---|---|
| `listen 8443 ssl http2;` | port 8443, speak TLS, allow HTTP/2 |
| `ssl_certificate` | the certificate file (public) |
| `ssl_certificate_key` | the private key file (secret) |
| `ssl_protocols TLSv1.2 TLSv1.3;` | refuse old TLS 1.0 / 1.1 |

> Nginx 1.24 (Ubuntu 24.04) writes HTTP/2 as `listen … ssl http2;`. The separate line `http2 on;` exists only from Nginx 1.25.1: on 1.24 it fails with `unknown directive "http2"`.

## 10.4 · Test it: three curl results to understand

`shop.example.com` points to 127.0.0.1 from topic 03.5.

```bash
curl -I https://shop.example.com:8443/
curl -kI https://shop.example.com:8443/
curl -I --cacert /etc/nginx/ssl/shop.crt https://shop.example.com:8443/
curl -I --cacert /etc/nginx/ssl/shop.crt https://localhost:8443/
```

| Command | Result | Means |
|---|---|---|
| plain `curl` | `curl: (60) SSL certificate problem: self-signed certificate` | curl does not trust the signer |
| `-k` | `HTTP/2 200` | "skip the trust check": test only, never in scripts |
| `--cacert shop.crt` | `HTTP/2 200` | "trust this certificate": the right way to test |
| `--cacert` + `localhost` | `curl: (60) SSL: no alternative certificate subject name matches target host name 'localhost'` | the name in the URL is not in `subjectAltName` |

- `HTTP/2` in the first line proves `http2` works.
- From your laptop's browser: `https://shop.example.com:8443/` (laptop hosts file → `[vm-ip]`) shows a warning page. That warning is the same problem as curl's `(60)`.

## 10.5 · Look at the handshake: openssl s_client

```bash
echo | openssl s_client -connect localhost:8443 -servername shop.example.com 2>/dev/null | grep -E "subject=|issuer=|Cipher is|Verify return"
echo | openssl s_client -connect localhost:8443 -servername shop.example.com -tls1_2 2>/dev/null | grep -E "Protocol|Cipher is"
echo | openssl s_client -connect localhost:8443 -servername shop.example.com -tls1_3 2>/dev/null | grep -E "Protocol|Cipher is"
echo | openssl s_client -connect localhost:8443 -servername shop.example.com 2>/dev/null | openssl x509 -noout -dates
```

| Output line | Means |
|---|---|
| `subject=CN = shop.example.com` | who the certificate says it is |
| `issuer=CN = shop.example.com` | who signed it (same = self-signed) |
| `New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384` | the protocol and cipher that were agreed |
| `Verify return code: 18 (self-signed certificate)` | trust check result (`0 (ok)` for a trusted certificate) |
| `notAfter=…` | expiry date seen **from outside**: use it to check any server |

- `s_client` is the tool for "is the certificate on the server the one I think?" after a renewal.

## 10.6 · Plain HTTP on the HTTPS port: 400, then fix it with 497

```bash
curl -s http://shop.example.com:8443/ | grep -i title
sudo tail -n 1 /var/log/nginx/shop-ssl-access.log
```

- `400 The plain HTTP request was sent to HTTPS port`: someone typed `http://` with the HTTPS port.
- Nginx calls this internal case **497**. Turn it into a redirect to the HTTPS address: add one line inside the `shop-ssl` server block:

```bash
sudo sed -i 's#    ssl_protocols TLSv1.2 TLSv1.3;#    ssl_protocols TLSv1.2 TLSv1.3;\n    error_page 497 =301 https://$host:8443$request_uri;#' /etc/nginx/sites-available/shop-ssl
grep -n "error_page 497" /etc/nginx/sites-available/shop-ssl
sudo nginx -t && sudo systemctl reload nginx
curl -sI http://shop.example.com:8443/docs/ | grep -E "HTTP|Location"
```

```nginx
    error_page 497 =301 https://$host:8443$request_uri;
```

- `=301` = answer with 301 instead of 400.
- `$request_uri` keeps the path and query, so `/docs/` goes to `https://shop.example.com:8443/docs/`.
- On a real server (ports 80 and 443) the usual redirect is a separate port-80 block with `return 301 https://$host$request_uri;`. Here port 80 belongs to Apache.

## 10.7 · Break it: the TLS errors you will meet

**A. Key file missing**

```bash
sudo sed -i 's#/etc/nginx/ssl/shop.key;#/etc/nginx/ssl/missing.key;#' /etc/nginx/sites-available/shop-ssl
sudo nginx -t
sudo sed -i 's#/etc/nginx/ssl/missing.key;#/etc/nginx/ssl/shop.key;#' /etc/nginx/sites-available/shop-ssl
sudo nginx -t
```

Sample line:

```text
2026/11/13 00:39:33 [emerg] 5202#5202: cannot load certificate key "/etc/nginx/ssl/missing.key": BIO_new_file() failed (SSL: error:80000002:system library::No such file or directory:calling fopen(/etc/nginx/ssl/missing.key, r) …)
```

- Read it from the left: `cannot load certificate key` + the path + `No such file or directory`. The OpenSSL codes in the middle can be skipped.
- After a certificate renewal, this is the first thing to check: are the paths and file names right?

**B. TLS sent to a port that is not TLS**

```bash
sudo sed -i 's/listen 8443 ssl http2;/listen 8443;/' /etc/nginx/sites-available/shop-ssl
sudo nginx -t && sudo systemctl reload nginx
curl -kI https://shop.example.com:8443/
sudo tail -n 1 /var/log/nginx/shop-ssl-access.log
sudo sed -i 's/listen 8443;/listen 8443 ssl http2;/' /etc/nginx/sites-available/shop-ssl
sudo nginx -t && sudo systemctl reload nginx
curl -kI https://shop.example.com:8443/
```

- curl: `curl: (35) … wrong version number`: the server did not answer with TLS.
- Access log sample line:

```text
127.0.0.1 - - [13/Nov/2026:00:40:07 +0000] "\x16\x03\x01\x01 \x01\x00\x01\x1C\x03\x03…" 400 150 "-" "-"
```

- A "request" that starts with `\x16\x03` is a **TLS hello** arriving on a plain-HTTP port: someone used `https://` on an `http` port, or `ssl` is missing from `listen`.

**C. Name mismatch and expiry** — already seen in 10.4 (`no alternative certificate subject name matches`) and 10.5 (`notAfter`).

| Symptom | Where | Cause |
|---|---|---|
| `curl: (60) self-signed certificate` / browser warning | client | signer not trusted |
| `curl: (60) no alternative certificate subject name matches` | client | URL name not in the certificate |
| `certificate has expired` | client | `notAfter` passed: renew |
| `400 The plain HTTP request was sent to HTTPS port` | client, access log | `http://` on the TLS port (fix: 497 redirect) |
| `"\x16\x03…" 400` in access log, `curl: (35) wrong version number` | access log, client | `https://` on a plain port / `ssl` missing in `listen` |
| `cannot load certificate key` / `cannot load certificate` | `nginx -t` | wrong path, wrong file, or permissions |

---

## Exercises

1. Show the expiry date of the certificate Nginx is really serving on 8443, without reading the file on disk.
2. Make a new certificate valid for both `shop.example.com` and `www.shop.example.com`, install it, and prove both names pass `--cacert`.
3. Prove TLS 1.3 is used by default and TLS 1.2 still works.
4. A colleague's check says `curl: (35) wrong version number` on port 8443. What do you look at first?
5. Why must the `.key` file be `600` and never copied into `/var/www`?

## Answers

1. `echo | openssl s_client -connect localhost:8443 -servername shop.example.com 2>/dev/null | openssl x509 -noout -dates`.
2. Same `openssl req` with `-addext "subjectAltName=DNS:shop.example.com,DNS:www.shop.example.com"`, `nginx -t`, reload; add `www.shop.example.com` to `/etc/hosts`; `curl -I --cacert /etc/nginx/ssl/shop.crt https://www.shop.example.com:8443/` → `HTTP/2 200`.
3. `s_client` without a flag shows `TLSv1.3`; with `-tls1_2` shows `Protocol : TLSv1.2`.
4. The `listen` line: `ssl` is missing, so the port speaks plain HTTP (access log shows `"\x16\x03…" 400`).
5. Whoever reads the key can pretend to be the site; anything under `/var/www` can be downloaded by visitors.
