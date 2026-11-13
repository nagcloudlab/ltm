# 12 · HTTPS: certificates, port 443, TLS errors

**Time:** 50 min

**You will learn:** what https adds, make a self-signed certificate with `openssl`, read a certificate, switch on `mod_ssl`, add a site on port 443, test with `curl -k` and `--cacert`, read the common TLS errors, send http visitors to https, and add HSTS.

---

## 12.1 · What https adds

- **http** sends everything as plain text: anyone on the network path can read passwords (topic 07 Basic auth!).
- **https** = http inside an encrypted **TLS** tunnel, on port **443**.
- The server proves its name with a **certificate**: "I am portal.example.com", signed by someone the browser trusts.

```
browser ──TLS handshake──► Apache :443   "here is my certificate for portal.example.com"
        ◄── encrypted tunnel ──►          then normal HTTP requests inside it
```

| Word | Means |
|---|---|
| private key (`.key`) | secret; stays on the server; never share it |
| certificate (`.crt`) | public; contains the name and the public key |
| CA (certificate authority) | the company that signs certificates browsers trust |
| self-signed | signed by itself: fine for labs and internal tests, browsers warn |

## 12.2 · Make a self-signed certificate

```bash
sudo openssl req -x509 -nodes -newkey rsa:2048 -days 365 -keyout /etc/ssl/private/portal.key -out /etc/ssl/certs/portal.crt -subj "/CN=portal.example.com" -addext "subjectAltName=DNS:portal.example.com,DNS:www.portal.example.com" -addext "basicConstraints=critical,CA:FALSE"
sudo chmod 600 /etc/ssl/private/portal.key
sudo ls -l /etc/ssl/private/portal.key /etc/ssl/certs/portal.crt
```

- `-x509` = make a finished certificate (not a request to a CA).
- `-nodes` = no password on the key, so Apache can start without someone typing it.
- `-days 365` = valid for one year.
- `CN` and `subjectAltName` = the names this certificate is valid for. Browsers and curl check **subjectAltName**.
- `CA:FALSE` = "this is a server certificate, not a CA". Without it Apache logs warning `AH01906 … server certificate is a CA certificate`.
- The key is `600` and lives in `/etc/ssl/private`: only root reads it.

## 12.3 · Read a certificate

```bash
openssl x509 -in /etc/ssl/certs/portal.crt -noout -subject -issuer -dates -ext subjectAltName
```

- `subject` = who the certificate is for.
- `issuer` = who signed it. Same as subject = self-signed.
- `notBefore` / `notAfter` = valid from / until. An expired certificate is a very common outage.

Check that a key and a certificate belong together (the two numbers must be equal):

```bash
openssl x509 -noout -modulus -in /etc/ssl/certs/portal.crt | md5sum
sudo openssl rsa -noout -modulus -in /etc/ssl/private/portal.key | md5sum
```

## 12.4 · Switch on mod_ssl

```bash
sudo a2enmod ssl
sudo systemctl restart apache2
sudo ss -lntp | grep apache2
grep -n -A2 "ssl_module" /etc/apache2/ports.conf
```

- A module needs a **restart** (topic 06).
- `ports.conf` already says `Listen 443` inside `<IfModule ssl_module>`: as soon as the module is on, port 443 opens.
- Nobody answers on 443 with your certificate yet: that needs a site.

## 12.5 · The portal site on port 443

```bash
sudo vi /etc/apache2/sites-available/portal-ssl.conf
```

Type:

```apache
<VirtualHost *:443>
    ServerName portal.example.com
    ServerAlias www.portal.example.com
    DocumentRoot /var/www/portal

    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/portal.crt
    SSLCertificateKeyFile /etc/ssl/private/portal.key

    ErrorLog ${APACHE_LOG_DIR}/portal-error.log
    CustomLog ${APACHE_LOG_DIR}/portal-ssl-access.log combined
</VirtualHost>
```

- `SSLEngine on` = this site speaks TLS.
- `SSLCertificateFile` / `SSLCertificateKeyFile` = the two files from 12.2.
- Same folder as the http portal: one website, two doors.

```bash
sudo a2ensite portal-ssl
sudo apache2ctl configtest && sudo systemctl reload apache2
sudo apache2ctl -S
```

- `-S` now shows a `*:443` line for `portal.example.com (…/portal-ssl.conf:1)`.

## 12.6 · Test with curl

```bash
curl -I https://portal.example.com/
curl -kI https://portal.example.com/
curl --cacert /etc/ssl/certs/portal.crt https://portal.example.com/
```

- First command fails: curl does not trust a self-signed certificate. This is the **same** warning a browser shows.
- `-k` = "do not check the certificate". Use it only for tests.
- `--cacert` = "trust this one certificate": a proper test that still checks the name and dates.

Sample line (first command):

```text
curl: (60) SSL certificate problem: self-signed certificate
```

See the handshake in detail:

```bash
curl -kv https://portal.example.com/ 2>&1 | grep -E "SSL connection|subject:|issuer:|expire date|HTTP/1.1"
echo | openssl s_client -connect localhost:443 -servername portal.example.com 2>/dev/null | grep -E "subject=|issuer=|Verify return code"
```

- `openssl s_client` is the "curl -v" of TLS: it shows exactly what certificate the server sends.
- `Verify return code: 18 (self-signed certificate)` = valid TLS, just not trusted.

## 12.7 · Read the common TLS errors

Wrong name in the URL:

```bash
curl --cacert /etc/ssl/certs/portal.crt https://localhost/
```

Sample line:

```text
curl: (60) SSL: no alternative certificate subject name matches target host name 'localhost'
```

- The certificate is for `portal.example.com`, you asked for `localhost`. Fix: use the right name, or add the name to `subjectAltName`.

Plain http to the https port:

```bash
curl -s http://localhost:443/ | grep -i speaking
sudo tail -n 1 /var/log/apache2/portal-ssl-access.log
```

- Answer: `400 Bad Request` with `You're speaking plain HTTP to an SSL-enabled server port.`
- Someone typed `http://server:443`. Tell them to use `https://`.

https to the http port:

```bash
curl -sS https://localhost:80/
```

Sample line:

```text
curl: (35) OpenSSL/3.0.13: error:0A00010B:SSL routines::wrong version number
```

- `wrong version number` almost always means "this port does not speak TLS".

| curl error | Means | Look at |
|---|---|---|
| `(60) self-signed certificate` | certificate not trusted | `-k` for tests, `--cacert`, or a CA-signed certificate |
| `(60) no alternative certificate subject name matches` | wrong name | `openssl x509 … -ext subjectAltName` |
| `(60) certificate has expired` | past `notAfter` | `openssl x509 … -dates`, renew |
| `(35) … wrong version number` | port is not TLS | the URL's port |
| `400 … speaking plain HTTP` | http sent to 443 | use `https://` |

## 12.8 · Break it: a missing key file

```bash
sudo cp /etc/apache2/sites-available/portal-ssl.conf /etc/apache2/sites-available/portal-ssl.conf.bak
sudo sed -i 's#private/portal.key#private/portl.key#' /etc/apache2/sites-available/portal-ssl.conf
sudo apache2ctl configtest
```

Sample line:

```text
AH00526: Syntax error on line 8 of /etc/apache2/sites-enabled/portal-ssl.conf:
SSLCertificateKeyFile: file '/etc/ssl/private/portl.key' does not exist or is empty
```

- configtest catches a **missing** file.

```bash
sudo cp /etc/apache2/sites-available/portal-ssl.conf.bak /etc/apache2/sites-available/portal-ssl.conf
sudo apache2ctl configtest
```

## 12.9 · Break it: key and certificate do not match

This one passes configtest and still kills Apache on restart.

```bash
sudo openssl genrsa -out /etc/ssl/private/other.key 2048
sudo chmod 600 /etc/ssl/private/other.key
sudo sed -i 's#private/portal.key#private/other.key#' /etc/apache2/sites-available/portal-ssl.conf
sudo apache2ctl configtest
sudo systemctl restart apache2
systemctl is-active apache2
sudo tail -n 2 /var/log/apache2/portal-error.log
```

Sample line:

```text
[Fri Nov 13 00:38:55.347293 2026] [ssl:emerg] [pid 7964:tid 281473581334560] AH02565: Certificate and private key portal.example.com:443:0 from /etc/ssl/certs/portal.crt and /etc/ssl/private/other.key do not match
```

- configtest said `Syntax OK`: it checks that files exist, not that they match.
- `[ssl:emerg]` = the worst level: Apache stopped. **Every** site is down, not only portal.
- The line is in the **site's** error log (`portal-error.log`), because that site's `ErrorLog` was set.
- Fix and prove it with the modulus check from 12.3:

```bash
sudo cp /etc/apache2/sites-available/portal-ssl.conf.bak /etc/apache2/sites-available/portal-ssl.conf
sudo apache2ctl configtest && sudo systemctl start apache2
systemctl is-active apache2
sudo rm /etc/ssl/private/other.key
```

> Before a certificate change in production: run the modulus check, then `configtest`, then **reload** (a failed reload keeps the old config running; a failed restart takes everything down).

## 12.10 · Send http visitors to https

In `portal.conf` (the port 80 site), inside the VirtualHost, add:

```apache
    RewriteEngine On
    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -sI http://portal.example.com/shop.html | grep -E "HTTP|Location"
```

- `HTTP/1.1 301 Moved Permanently` and `Location: https://portal.example.com/shop.html`.
- `%{HTTP_HOST}` = the name the visitor used; `%{REQUEST_URI}` = the path they asked for.
- Needs `mod_rewrite` (enabled in topic 06).

## 12.11 · HSTS: tell browsers "always https"

In `portal-ssl.conf`, inside the VirtualHost:

```apache
    Header always set Strict-Transport-Security "max-age=31536000"
```

```bash
sudo apache2ctl configtest && sudo systemctl reload apache2
curl -kI https://portal.example.com/ | grep -i strict-transport
```

- The browser remembers it for `max-age` seconds (here one year) and never tries plain http again.
- Put HSTS only on the **https** site, and only when https works reliably: a mistake stays in browsers for a year.

---

## Exercises

1. Show the expiry date of `portal.crt` in one command.
2. Give the admin site its own self-signed certificate and an `*:443` site; prove it with `--cacert`.
3. `curl https://10.0.0.5/` fails with `no alternative certificate subject name matches`. Explain and give two fixes.
4. After a certificate change Apache will not start, but configtest says `Syntax OK`. What do you check first, and where is the error line?
5. Prove that `http://portal.example.com/` now redirects to https, and that the redirect is permanent.

## Answers

1. `openssl x509 -in /etc/ssl/certs/portal.crt -noout -enddate`.
2. Same as 12.2 with `CN=admin.example.com` and file names `admin.key`/`admin.crt`; `admin-ssl.conf` with `ServerName admin.example.com`; `curl --cacert /etc/ssl/certs/admin.crt https://admin.example.com/`.
3. The certificate has no IP address in `subjectAltName`. Use the name (`https://portal.example.com/` with a hosts entry), or make a certificate with `subjectAltName=IP:10.0.0.5`.
4. Whether key and certificate match (the two `md5sum` lines in 12.3); the `AH02565` line in the site's error log (and `journalctl -u apache2`).
5. `curl -sI http://portal.example.com/ | grep -E "HTTP|Location"` → `301 Moved Permanently`, `Location: https://portal.example.com/`.
