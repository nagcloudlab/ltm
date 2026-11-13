# 05 · Access and security

**Time:** 45 min

**You will learn:** allow/deny by address, password protection (401), blocking hidden and backup files, security headers (and the `add_header` trap), hiding the version, upload size limits (413), method limits (405), and rate limiting.

---

## 05.1 · allow and deny

```nginx
    location /admin/ {
        allow 127.0.0.1;
        allow 10.0.0.0/24;
        deny all;
    }
```

```bash
sudo mkdir -p /var/www/shop/admin
echo "<h1>Shop admin</h1>" | sudo tee /var/www/shop/admin/index.html
sudo nginx -t && sudo systemctl reload nginx
curl -I http://localhost:8081/admin/
```

From your laptop or neighbour (not in the list): **403**, and:

```bash
sudo tail -n 1 /var/log/nginx/shop-error.log
```

`access forbidden by rule, client: …`

| Rule | Means |
|---|---|
| lines checked **top to bottom** | the first match decides |
| `deny all;` | must be **last** |
| Apache equivalent | `Require local` / `Require ip …` |

## 05.2 · Password protection: 401

`htpasswd` comes from `apache2-utils` (already installed with Apache; otherwise `sudo apt install -y apache2-utils`).

```bash
sudo htpasswd -c /etc/nginx/.htpasswd admin
sudo htpasswd /etc/nginx/.htpasswd ops
```

```nginx
    location /admin/ {
        auth_basic "Shop admins only";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
```

(Replace the allow/deny version from 05.1 with this one.)

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -I http://localhost:8081/admin/
curl -u admin:yourpassword -I http://localhost:8081/admin/
curl -u admin:wrong -I http://localhost:8081/admin/
sudo tail -n 1 /var/log/nginx/shop-error.log
```

| Response | Means |
|---|---|
| 401 + `WWW-Authenticate: Basic realm="Shop admins only"` | log in first |
| 200 | right user and password |
| error log `user "admin": password mismatch` | wrong password (watch for guessing) |
| no error-log line at all | no password sent yet: normal, only the access log shows the 401 |

**Office network OR password** (either is enough):

```nginx
    location /admin/ {
        satisfy any;
        allow 10.0.0.0/24;
        deny all;
        auth_basic "Shop admins only";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
```

`satisfy all` (the default) would require **both**.

## 05.3 · Block hidden and backup files

```nginx
    location ~ /\. {
        deny all;
    }
    location ~* \.(bak|old|swp|sql|tar|gz|zip)$ {
        deny all;
    }
```

```bash
echo "DB_PASSWORD=secret" | sudo tee /var/www/shop/.env
sudo touch /var/www/shop/index.html.bak
sudo nginx -t && sudo systemctl reload nginx
curl -I http://localhost:8081/.env
curl -I http://localhost:8081/index.html.bak
sudo rm /var/www/shop/.env /var/www/shop/index.html.bak
```

Both 403. Unlike Apache, Nginx does **not** block dot-files by default: without this rule `.env` would be downloadable.

To hide that the file exists at all, use `return 404;` instead of `deny all;`.

## 05.4 · Security headers, and the add_header trap

In the shop `server` block:

```nginx
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -sI http://localhost:8081/ | grep -E "X-|Referrer"
curl -sI http://localhost:8081/images/logo.png | grep -E "X-|Referrer"
```

The second curl shows **only** `X-Matched` (from topic 04): the security headers vanished.

| Rule | Means |
|---|---|
| `add_header` in a location **replaces all** `add_header` lines from the server block | the trap |
| `always` | also add the header to error responses (403, 404, 500) |

Fix: repeat the security headers in that location, or put them in a snippet and `include` it in every location that has its own `add_header`:

```bash
sudo tee /etc/nginx/snippets/security-headers.conf <<'EOF'
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
EOF
```

Edit the existing `/images/` location:

```nginx
    location ^~ /images/ {
        include snippets/security-headers.conf;
        add_header X-Matched "prefix /images/";
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }
```

## 05.5 · Hide the version

```bash
curl -sI http://localhost:8081/ | grep -i server
curl -s http://localhost:8081/nothing.png | tail -n 3
```

In `nginx.conf`, inside `http { }`, uncomment or add:

```nginx
    server_tokens off;
```

```bash
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
sudo vi /etc/nginx/nginx.conf
sudo nginx -t && sudo systemctl reload nginx
curl -sI http://localhost:8081/ | grep -i server
```

`Server: nginx/1.24.0 (Ubuntu)` → `Server: nginx`, and error pages no longer show the version.

## 05.6 · Upload size: 413

```bash
head -c 2000000 /dev/zero > ~/big.bin
curl -s -o /dev/null -w "%{http_code}\n" -X POST --data-binary @$HOME/big.bin http://localhost:8081/
sudo tail -n 1 /var/log/nginx/shop-error.log
```

**413 Request Entity Too Large**: `client intended to send too large body: 2000000 bytes`.

| Server | Setting | Default |
|---|---|---|
| Nginx | `client_max_body_size` | **1m** |
| Apache | `LimitRequestBody` | 1 GB |
| IIS | `maxAllowedContentLength` | 30 MB (gives 404.13) |

```nginx
    client_max_body_size 10m;
```

(In `server` or a specific `location`, e.g. `/upload/`.) Reload and retry: the 413 becomes **405** (next section).

## 05.7 · Methods: 405

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:8081/
curl -s -o /dev/null -w "%{http_code}\n" -X DELETE http://localhost:8081/index.html
```

**405 Not Allowed**: static files can only be read. Allow only GET and HEAD explicitly:

```nginx
    location / {
        limit_except GET {
            deny all;
        }
        try_files $uri $uri/ =404;
    }
```

(`GET` includes `HEAD`.) Other methods now get **403**.

## 05.8 · Rate limiting: slow down floods

Define a zone in `http` (a file in `conf.d`):

```bash
echo 'limit_req_zone $binary_remote_addr zone=perip:10m rate=5r/s;' | sudo tee /etc/nginx/conf.d/ratelimit.conf
```

Use it on a real file (`health.json` from topic 04). `return` would **not** work here: it answers before the rate limit is checked.

```nginx
    location = /health.json {
        limit_req zone=perip burst=5 nodelay;
        limit_req_status 429;
    }
```

```bash
sudo nginx -t && sudo systemctl reload nginx
for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code} " http://localhost:8081/health.json; done; echo
sudo tail -n 2 /var/log/nginx/shop-error.log
```

About the first 6 get 200 (5 per second + burst), the rest **429 Too Many Requests**; the error log says `limiting requests, excess: …`.

| Part | Means |
|---|---|
| `$binary_remote_addr` | count per client IP |
| `zone=perip:10m` | shared memory name and size (~160,000 IPs) |
| `rate=5r/s` | allowed average |
| `burst=5 nodelay` | allow a short burst of 5 extra, without delay |
| `limit_req_status 429` | answer code (default is 503) |

You will meet 429 again with the API gateway.

---

## Exercises

1. Allow `/admin/` only from the server itself, with no password.
2. Add a second user, then allow **only** that user (hint: separate password file).
3. Block every request for `/.git/` with a 404 instead of 403.
4. A new location got its own `add_header`, and the security scan now reports missing headers on that path. Why, and the fix?
5. Allow uploads up to 20 MB only under `/upload/`. Where does the line go?

## Answers

1. `location /admin/ { allow 127.0.0.1; deny all; }`.
2. `sudo htpasswd -c /etc/nginx/.htpasswd-auditors auditor`, and point `auth_basic_user_file` at that file.
3. `location ~ /\.git { return 404; }`.
4. `add_header` in a location replaces the server's headers; include the security-headers snippet in that location.
5. `location /upload/ { client_max_body_size 20m; … }`.
