#!/usr/bin/env bash
# Creates ~/lab/apache/access.log and ~/lab/apache/error.log:
# one hour (10:00-11:00 IST, 11 Nov 2026) of the PayBank portal, for log-reading practice.
# Access log format: combined + %D (time taken in microseconds) as the last field.
set -euo pipefail

OUT="$HOME/lab/apache"
mkdir -p "$OUT"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

awk 'function t(sec,  h, m, s) { h = 10 + int(sec / 3600); m = int((sec % 3600) / 60); s = sec % 60; return sprintf("%02d:%02d:%02d", h, m, s) }
     function a(sec, ip, user, method, path, st, bytes, ref, ua, us) {
       printf "%s - %s [11/Nov/2026:%s +0530] \"%s %s HTTP/1.1\" %d %d \"%s\" \"%s\" %d\n", ip, user, t(sec), method, path, st, bytes, ref, ua, us
     }
     BEGIN {
       br = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
       app = "PayBank-Mobile/3.2"
       site = "http://portal.example.com/shop/"
       for (i = 0; i < 240; i++) {
         sec = i * 15
         ip = "10.0.1." (i * 7 % 30 + 10)
         slow = (i >= 120 && i < 140)            # 10:30:00 - 10:34:45
         k = i % 8
         if (k == 0) a(sec, ip, "-", "GET", "/", 200, 11022, "-", br, 300 + (i % 5) * 50)
         else if (k == 1) a(sec, ip, "-", "GET", "/shop/", 200, 539, "-", br, 250 + (i % 4) * 40)
         else if (k == 2) a(sec, ip, "-", "GET", "/shop/style.css", 200, 228, site, br, 120 + (i % 3) * 20)
         else if (k == 3) a(sec, ip, "-", "GET", "/cgi-bin/statement.sh?acct=" (4000 + i), 200, 1840, "-", app, slow ? 4000000 + (i % 5) * 600000 : 120000 + (i % 6) * 25000)
         else if (k == 4) a(sec, ip, "-", "GET", "/favicon.ico", 404, 404, "-", br, 90)
         else if (k == 5) a(sec, ip, "-", "GET", "/hello.html", 200, 342, "-", br, 110)
         else if (k == 6) { if (i % 16 == 6) a(sec, ip, "-", "GET", "/shop/logo.png", 304, 180, site, br, 80); else a(sec, ip, "-", "GET", "/shop/logo.png", 200, 5120, site, br, 150) }
         else a(sec, ip, "-", "POST", "/cgi-bin/transfer.sh", 200, 96, "-", app, slow ? 6000000 + (i % 3) * 700000 : 180000 + (i % 5) * 20000)
       }
       # 10:12:00 someone tries the private folder
       a(720, "10.0.1.40", "-", "GET", "/private/", 403, 273, "-", br, 160)
       # 10:20:00 password guessing on /admin/, then success
       for (j = 0; j < 5; j++) a(1200 + j * 2, "10.0.1.66", "admin", "GET", "/admin/", 401, 459, "-", br, 2100)
       a(1212, "10.0.1.66", "admin", "GET", "/admin/", 200, 229, "-", br, 1900)
       # 10:40:00 - 10:40:50 a broken .htaccess in /blog/
       for (j = 0; j < 6; j++) a(2400 + j * 10, "10.0.1." (20 + j), "-", "GET", "/blog/", 500, 607, "-", br, 700)
       a(2490, "10.0.1.21", "-", "GET", "/blog/", 200, 260, "-", br, 400)
       # 10:47:00 a scanner from the internet
       n = split("/.env:403:199 /.git/config:404:196 /wp-login.php:404:196 /backup.zip:403:199 /server-status:403:199 /admin/:401:459 /phpmyadmin/:404:196 /config.php.bak:403:199", sc, " ")
       for (j = 1; j <= n; j++) { split(sc[j], f, ":"); a(2820 + j, "203.0.113.50", "-", "GET", f[1], f[2], f[3], "-", "zgrab/0.x", 95) }
     }' | LC_ALL=C sort -s -t'[' -k2,2 > "$OUT/access.log"

cat > "$OUT/error.log" <<'LOG'
[Wed Nov 11 10:00:01.204117 2026] [mpm_event:notice] [pid 812:tid 140245] AH00489: Apache/2.4.58 (Ubuntu) configured -- resuming normal operations
[Wed Nov 11 10:00:01.204188 2026] [core:notice] [pid 812:tid 140245] AH00094: Command line: '/usr/sbin/apache2'
[Wed Nov 11 10:12:00.418920 2026] [authz_core:error] [pid 2410:tid 140311] [client 10.0.1.40:51022] AH01630: client denied by server configuration: /var/www/html/private/
[Wed Nov 11 10:20:00.101334 2026] [auth_basic:error] [pid 2411:tid 140322] [client 10.0.1.66:51230] AH01617: user admin: authentication failure for "/admin/": Password Mismatch
[Wed Nov 11 10:20:02.093120 2026] [auth_basic:error] [pid 2411:tid 140323] [client 10.0.1.66:51232] AH01617: user admin: authentication failure for "/admin/": Password Mismatch
[Wed Nov 11 10:20:04.087711 2026] [auth_basic:error] [pid 2411:tid 140324] [client 10.0.1.66:51234] AH01617: user admin: authentication failure for "/admin/": Password Mismatch
[Wed Nov 11 10:20:06.112054 2026] [auth_basic:error] [pid 2410:tid 140312] [client 10.0.1.66:51236] AH01617: user admin: authentication failure for "/admin/": Password Mismatch
[Wed Nov 11 10:20:08.099876 2026] [auth_basic:error] [pid 2410:tid 140313] [client 10.0.1.66:51238] AH01617: user admin: authentication failure for "/admin/": Password Mismatch
[Wed Nov 11 10:31:12.550301 2026] [mpm_event:error] [pid 812:tid 140245] AH00484: server reached MaxRequestWorkers setting, consider raising the MaxRequestWorkers setting
[Wed Nov 11 10:40:00.310442 2026] [core:alert] [pid 2412:tid 140330] [client 10.0.1.20:52010] /var/www/html/blog/.htaccess: Invalid command 'Redirekt', perhaps misspelled or defined by a module not included in the server configuration
[Wed Nov 11 10:40:10.297015 2026] [core:alert] [pid 2412:tid 140331] [client 10.0.1.21:52018] /var/www/html/blog/.htaccess: Invalid command 'Redirekt', perhaps misspelled or defined by a module not included in the server configuration
[Wed Nov 11 10:40:20.305500 2026] [core:alert] [pid 2410:tid 140314] [client 10.0.1.22:52026] /var/www/html/blog/.htaccess: Invalid command 'Redirekt', perhaps misspelled or defined by a module not included in the server configuration
[Wed Nov 11 10:40:30.299871 2026] [core:alert] [pid 2411:tid 140325] [client 10.0.1.23:52034] /var/www/html/blog/.htaccess: Invalid command 'Redirekt', perhaps misspelled or defined by a module not included in the server configuration
[Wed Nov 11 10:40:40.301266 2026] [core:alert] [pid 2412:tid 140332] [client 10.0.1.24:52042] /var/www/html/blog/.htaccess: Invalid command 'Redirekt', perhaps misspelled or defined by a module not included in the server configuration
[Wed Nov 11 10:40:50.300912 2026] [core:alert] [pid 2410:tid 140315] [client 10.0.1.25:52050] /var/www/html/blog/.htaccess: Invalid command 'Redirekt', perhaps misspelled or defined by a module not included in the server configuration
[Wed Nov 11 10:47:01.002215 2026] [authz_core:error] [pid 2411:tid 140326] [client 203.0.113.50:40112] AH01630: client denied by server configuration: /var/www/html/.env
[Wed Nov 11 10:47:04.001877 2026] [authz_core:error] [pid 2411:tid 140327] [client 203.0.113.50:40118] AH01630: client denied by server configuration: /var/www/html/backup.zip
[Wed Nov 11 10:47:05.002630 2026] [authz_core:error] [pid 2412:tid 140333] [client 203.0.113.50:40120] AH01630: client denied by server configuration: /var/www/html/server-status
[Wed Nov 11 10:47:08.001954 2026] [authz_core:error] [pid 2410:tid 140316] [client 203.0.113.50:40126] AH01630: client denied by server configuration: /var/www/html/config.php.bak
LOG

echo "Created $OUT/access.log ($(wc -l < "$OUT/access.log") lines) and $OUT/error.log ($(wc -l < "$OUT/error.log") lines)"
