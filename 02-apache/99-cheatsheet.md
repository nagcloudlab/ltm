# Apache on one page

## Service
| | |
|---|---|
| `systemctl status \| start \| stop \| restart \| reload apache2` | service state |
| `systemctl enable \| disable apache2` | at boot |
| `journalctl -u apache2 -n 20` | start-up messages |

## Is it healthy?
| | |
|---|---|
| `systemctl status apache2` | 1 process |
| `sudo ss -lntp \| grep apache2` | 2 port |
| `curl -I http://localhost/` | 3 answer |

## Change safely
| | |
|---|---|
| `sudo cp f f.bak` → `sudo vi f` | back up, edit |
| `sudo apache2ctl configtest && sudo systemctl reload apache2` | test, then apply |
| `curl -I …` · `sudo tail /var/log/apache2/error.log` | verify |

## Ask Apache
| | |
|---|---|
| `apache2ctl -S` | websites, default server, files |
| `apache2ctl -M` | modules loaded |
| `apache2ctl -V` | version, MPM |
| `curl "http://localhost/server-status?auto"` | workers, requests, scoreboard |

## Where things are
| | |
|---|---|
| `/etc/apache2/apache2.conf` · `ports.conf` · `envvars` | main · ports · user/log dir |
| `sites-available/` → `a2ensite` / `a2dissite` → `sites-enabled/` | websites |
| `mods-available/` → `a2enmod` / `a2dismod` (restart) | modules |
| `conf-available/security.conf` | ServerTokens, ServerSignature |
| `/var/www/html/` | default DocumentRoot |
| `/var/log/apache2/` | access.log, error.log |

## Config lines
```apache
Listen 8090
<VirtualHost *:80>
    ServerName portal.example.com
    ServerAlias www.portal.example.com
    DocumentRoot /var/www/portal
    ErrorLog ${APACHE_LOG_DIR}/portal-error.log
    CustomLog ${APACHE_LOG_DIR}/portal-access.log combined
    Redirect permanent /old.html /new.html
    ErrorDocument 404 /404.html
    Alias /docs /srv/docs
    <Directory /srv/docs>
        Options -Indexes
        AllowOverride None
        Require all granted          # denied · local · ip 10.0.0.0/24 · valid-user
    </Directory>
</VirtualHost>
```

## Logs
| | |
|---|---|
| `tail -F access.log error.log` | watch live |
| `cut -d' ' -f9 access.log \| sort \| uniq -c \| sort -rn` | status counts (field 9) |
| `cut -d' ' -f1 … \| sort \| uniq -c \| sort -rn \| head` | top clients |
| `awk '$9 >= 500' access.log` | server errors |
| `%D` in LogFormat → `awk '{print $NF,$7}' … \| sort -n \| tail` | slowest requests |

## Status codes
| | |
|---|---|
| 200 OK · 206 partial · 301/302 redirect · 304 not modified | |
| 400 bad request · 401 log in · 403 not allowed · 404 not there · 405 method · 413 too big · 414 URL too long | request side |
| 500 server failed · 502/503/504 with a backend (reverse proxy) | server side |

## 403 · which one?
| error log | fix |
|---|---|
| `AH01630 client denied by server configuration` | Require / `<Directory>` |
| `AH01276 Cannot serve directory … forbidden by Options` | no index file, listings off: add index.html |
| `(13) … AH00035 … search permissions are missing` | `chmod 755` folders |
| `(13) … AH00132 file permissions deny server access` | `chmod 644` file |

## Won't start?
`systemctl status` → `journalctl -u apache2` → `apache2ctl configtest` → `ss -lntp 'sport = :80'` · `AH00526` syntax (file + line) · `(98) AH00072` port taken (`fuser -v 80/tcp`) · `no listening sockets` no Listen line · `AH02565` key/cert mismatch

## Security
`ServerTokens Prod` · `ServerSignature Off` · `Options -Indexes` · `<FilesMatch "^\.">Require all denied` · `htpasswd -c` (first user only) · headers via `a2enmod headers` · `ufw allow "Apache"`

## Performance
`apache2ctl -V | grep -i mpm` · `MaxRequestWorkers 150` · `KeepAlive On` · `deflate` (gzip) · `a2enmod expires` · `ab -n 2000 -c 50 http://localhost/`

## HTTPS
```bash
sudo openssl req -x509 -nodes -newkey rsa:2048 -days 365 -keyout /etc/ssl/private/portal.key -out /etc/ssl/certs/portal.crt -subj "/CN=portal.example.com" -addext "subjectAltName=DNS:portal.example.com" -addext "basicConstraints=critical,CA:FALSE"
openssl x509 -in /etc/ssl/certs/portal.crt -noout -subject -issuer -dates -ext subjectAltName
sudo a2enmod ssl && sudo systemctl restart apache2
curl -kI https://portal.example.com/
echo | openssl s_client -connect localhost:443 -servername portal.example.com 2>/dev/null | grep -E "subject=|Verify return code"
```
`(60) self-signed` · `(60) no alternative certificate subject name` wrong name · `(35) wrong version number` not a TLS port · `400 speaking plain HTTP` http on 443

## Logs, advanced
| | |
|---|---|
| `LogFormat "… %{Host}i \"%{User-Agent}i\" %D" paybank` in `conf-available/` + `a2enconf` | one format for all sites, `%D` last |
| `awk '$NF > 1000000' log` | requests slower than 1 s |
| `awk -F'"' '{print $6}' log` | user agent in one piece |
| `other_vhosts_access.log` | sites with no CustomLog; status is `$10` |
| `LogLevel warn rewrite:trace3` · `authz_core:debug` · `ssl:info` | one module louder, in one site |
| `logrotate -d /etc/logrotate.d/apache2` | dry run |
| `lsof +L1` | deleted but open logs still using disk → reload |

## Error-log codes
| Code | Means |
|---|---|
| `AH00526` | syntax error (file, line) |
| `AH00558` | no global ServerName (warning) |
| `AH00072` | port already in use |
| `AH00112` | DocumentRoot does not exist (warning) |
| `AH01630` | Require said no |
| `AH01276` | folder without index, listings off |
| `AH00035` / `AH00132` | folder / file permissions (13) |
| `AH01617` / `AH01618` / `AH01620` | wrong password / no such user / password file missing |
| `AH00484` | all workers busy (MaxRequestWorkers) |
| `AH00515` | MaxRequestWorkers lowered to fit ServerLimit |
| `AH02565` | certificate and key do not match |
| `.htaccess: Invalid command` (core:alert) | bad line in .htaccess → 500 |

