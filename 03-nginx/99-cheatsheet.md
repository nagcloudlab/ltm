# Nginx on one page (with Apache equivalents)

## Service and tests
| Nginx | Apache |
|---|---|
| `systemctl status \| reload \| restart nginx` | `… apache2` |
| `sudo nginx -t` | `apache2ctl configtest` |
| `sudo nginx -T` (print all config) | `apache2ctl -S` (closest) |
| `nginx -V` (version + modules) | `apache2ctl -V` / `-M` |
| `nginx -s reload \| reopen \| quit` | |
| `journalctl -u nginx -n 20` | `journalctl -u apache2` |

## Change safely
`sudo cp f f.bak` → `sudo vi f` → `sudo nginx -t && sudo systemctl reload nginx` → `curl -I …` → `tail error.log`

- Failed reload = old config keeps running; the reason is in `/var/log/nginx/error.log`.
- Changed a `listen` **address** on the same port → `restart` (reload logs `bind() … (98: Address already in use)`).

## Files
| | |
|---|---|
| `/etc/nginx/nginx.conf` | main: user, workers, `http { }` |
| `sites-available/` → `ln -s` → `sites-enabled/` | websites (no a2ensite) |
| `conf.d/*.conf` | extra `http` settings (log_format, gzip, limit_req_zone) |
| `snippets/` | reusable pieces (`include snippets/x.conf;`) |
| `/var/log/nginx/` | access.log, error.log, per-site logs |

## Blocks
```nginx
server {                                   # = <VirtualHost>
    listen 8081 default_server;            # 127.0.0.1:8081 = local only
    server_name shop.example.com www.shop.example.com;
    root /var/www/shop;                    # = DocumentRoot
    index index.html;

    location / { try_files $uri $uri/ =404; }
    location = /health { return 200 'ok'; }          # exact
    location ^~ /images/ { autoindex on; }           # prefix, beats regex
    location ~* \.(css|png)$ { expires 7d; }         # regex, any case
    location /manuals/ { alias /srv/manuals/; }      # replaces /manuals/
    location /admin/ { allow 10.0.0.0/24; deny all; auth_basic "Admins"; auth_basic_user_file /etc/nginx/.htpasswd; satisfy any; }
    location ~ /\. { deny all; }

    error_page 404 /404.html;
    location = /404.html { internal; }
    client_max_body_size 10m;
    access_log /var/log/nginx/shop-access.log timed;
    error_log  /var/log/nginx/shop-error.log;
}
```

## Location order
`=` exact → longest prefix → `^~` stops → regex in file order → longest prefix

## Status codes from Nginx
| | |
|---|---|
| 301/302 `return` · 304 caching | |
| 401 `auth_basic` · 403 deny / no index / errno 13 · 404 errno 2 | |
| 405 POST to static · 413 body too big · 429 `limit_req_status` · 444 close (Nginx only) | |
| 503 from `limit_req` without `limit_req_status` (error log: `limiting requests`) | |
| 500 `rewrite or internal redirection cycle` | |
| 502/503/504 with a backend (reverse proxy) | |

## Error-log reasons
| | |
|---|---|
| `(2: No such file or directory)` | wrong path: root vs alias (try_files 404s are **not** logged) |
| `"…" is not found (2: …)` | index file missing after root/alias mistake |
| `(13: Permission denied)` | file: chmod 644 (403) · `[crit]` on a folder: chmod 755 (404) |
| `directory index of … is forbidden` | no index, autoindex off |
| `access forbidden by rule` | allow/deny |
| `client intended to send too large body` | client_max_body_size |
| `limiting requests` | limit_req |
| `bind() … (98: Address already in use)` | port taken (main error.log) |
| `invalid number of arguments` / `not terminated by ";"` | missing `;` (look one line up) |
| `unknown directive "x"` | typo or module missing |
| `rewrite or internal redirection cycle` | rewrite `last` loop → 500 |
| `accept4() failed (24: Too many open files)` | `worker_rlimit_nofile` too low |
| `cannot load certificate key` | wrong key path |
| `[warn] conflicting server name … ignored` | duplicate site |

## Logs
`log_format timed '… rt=$request_time host=$host';` (in http) · `access_log … timed if=$loggable;` · `cut -d' ' -f9 … | sort | uniq -c | sort -rn` · `logrotate -f /etc/logrotate.d/nginx`

## Performance
`worker_processes auto` × `worker_connections 768` · `keepalive_timeout 15s` · `gzip_types …` · `expires 7d` · `open_file_cache` · `stub_status` · `ab -k -n 20000 -c 500`

## Security
`server_tokens off` · `add_header … always` (inner add_header replaces outer!) · `location ~ /\. { deny all; }` · `limit_req_zone $binary_remote_addr zone=perip:10m rate=5r/s;`

## HTTPS (Nginx 1.24)
```nginx
listen 8443 ssl http2;                 # not "http2 on;" (1.25+ only)
ssl_certificate     /etc/nginx/ssl/shop.crt;
ssl_certificate_key /etc/nginx/ssl/shop.key;
ssl_protocols TLSv1.2 TLSv1.3;
error_page 497 =301 https://$host:8443$request_uri;   # http:// sent to the TLS port
```
`openssl req -x509 -nodes -newkey rsa:2048 -days 365 -keyout k -out c -subj "/CN=name" -addext "subjectAltName=DNS:name"` · `curl --cacert c https://name:8443/` · `echo | openssl s_client -connect host:8443 -servername name | openssl x509 -noout -dates`
- `curl: (60) self-signed` = trust · `(60) no alternative … name` = wrong name · `(35) wrong version number` + access log `"\x16\x03…" 400` = TLS on a plain port · `400 plain HTTP … HTTPS port` = http on TLS port

## Redirects
`return 301 /new;` (simple) · `rewrite ^/old/(.*)$ /new/$1 permanent|redirect|last|break;` · `$request_uri` = path + query · `rewrite_log on;` + `error_log … notice;` · loop = same URL + 301 repeated in access log; curl `(47) Maximum redirects`

## Advanced logs
`log_format json escape=json '{"time":"$time_iso8601","status":$status,"rt":$request_time,…}';` · `map $status $is_error { ~^[45] 1; default 0; }` + `access_log f combined if=$is_error;` · `mv log log.1` → `nginx -s reopen` · `grep -rh "words" /var/log/nginx/`

## Capacity
`worker_processes auto;` · `worker_rlimit_nofile 8192;` (≈ 2 × connections) · `events { worker_connections 4096; }` · prove: `sudo grep "open files" /proc/$(pgrep -f "nginx: worker" | head -n 1)/limits` · limits need `restart`

## Ports in this module
80, 8090 Apache · 8081 shop + blog · 8082 stats · 8083 lab (practice) · 8443 shop HTTPS · 8080 reserved (Tomcat)
