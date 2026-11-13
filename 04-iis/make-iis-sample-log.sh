#!/usr/bin/env bash
# Creates ~/lab/iis/u_ex261111.log: one hour of a PayBank Portal IIS log
# (the 17 default W3C fields of Windows Server 2022, times in UTC) for practising log analysis on Linux,
# and ~/lab/iis/httperr1.log: the HTTP.sys error log for the same hour.
set -euo pipefail

OUT_DIR="$HOME/lab/iis"
OUT="$OUT_DIR/u_ex261111.log"
mkdir -p "$OUT_DIR"

BODY=$(mktemp)
trap 'rm -f "$BODY"' EXIT

awk 'function ts(sec,   h, m, s) {
       h = 4 + int((30*60 + sec) / 3600); m = int(((30*60 + sec) % 3600) / 60); s = (30*60 + sec) % 60
       return sprintf("2026-11-11 %02d:%02d:%02d", h, m, s)
     }
     function sbytes(stem, st) {
       if (st == 304) return 211
       if (st == 401) return 6102
       if (st == 404) return 5080 + length(stem)
       if (st == 413) return 5239
       if (st == 500) return 7254
       if (stem == "/") return 1290
       if (stem == "/css/site.css") return 3480
       if (stem == "/js/app.js") return 18240
       if (stem == "/images/logo.png") return 24510
       if (stem == "/api/accounts") return 2150
       if (stem == "/api/balance") return 640
       if (stem == "/api/transfer") return 410
       if (stem == "/login") return 2870
       if (stem == "/reports/nov.pdf") return 482110
       return 1380
     }
     function cbytes(method, stem, ua) {
       if (stem == "/api/upload") return 712
       if (method == "POST") return 1420
       if (ua ~ /zgrab/) return 160
       if (ua ~ /PayBank/) return 310
       return 430
     }
     function line(sec, method, stem, query, user, cip, ua, ref, st, ss, w32, tt) {
       printf "%s 10.0.0.5 %s %s %s 80 %s %s %s %s %d %d %d %d %d %d\n", ts(sec), method, stem, query, user, cip, ua, ref, st, ss, w32, sbytes(stem, st), cbytes(method, stem, ua), tt
     }
     BEGIN {
       web = "Mozilla/5.0+(Windows+NT+10.0;+Win64;+x64)"
       app = "PayBank-Mobile/3.2"
       for (i = 0; i < 240; i++) {
         sec = i * 15
         cip = "10.20.1." (i * 7 % 40 + 10)
         slow = (i >= 100 && i < 160)          # 04:55:00 - 05:09:45 UTC
         k = i % 10
         if (k == 0) line(sec, "GET", "/", "-", "-", cip, web, "-", 200, 0, 0, 15 + (i % 5) * 3)
         else if (k == 1) line(sec, "GET", "/css/site.css", "-", "-", cip, web, "http://portal.example.com/", 200, 0, 0, 4 + i % 3)
         else if (k == 2) line(sec, "GET", "/js/app.js", "-", "-", cip, web, "http://portal.example.com/", 200, 0, 0, 6 + i % 4)
         else if (k == 3) line(sec, "GET", "/api/accounts", "id=" (1000 + i), "-", cip, app, "-", 200, 0, 0, slow ? 5000 + (i % 7) * 500 : 120 + (i % 7) * 20)
         else if (k == 4) line(sec, "GET", "/api/balance", "-", "-", cip, app, "-", 200, 0, 0, slow ? 6000 + (i % 5) * 400 : 80 + (i % 5) * 10)
         else if (k == 5) {
           if (slow) line(sec, "POST", "/api/transfer", "-", "-", cip, app, "-", 500, 0, 0, 30000 + int(i / 10) * 7)
           else line(sec, "POST", "/api/transfer", "-", "-", cip, app, "-", 200, 0, 0, 450 + (i % 6) * 50)
         }
         else if (k == 6) line(sec, "GET", "/favicon.ico", "-", "-", cip, web, "-", 404, 0, 2, 1)
         else if (k == 7) {
           if (i % 20 == 7) line(sec, "GET", "/images/logo.png", "-", "-", cip, web, "http://portal.example.com/", 304, 0, 0, 1)
           else line(sec, "GET", "/images/logo.png", "-", "-", cip, web, "http://portal.example.com/", 200, 0, 0, 3)
         }
         else if (k == 8) line(sec, "GET", "/api/accounts", "-", "-", cip, app, "-", 200, 0, 0, slow ? 7000 + (i % 3) * 800 : 140 + (i % 4) * 15)
         else line(sec, "GET", "/login", "-", "-", cip, web, "-", 200, 0, 0, 25)
       }
       # uploads over the 30 MB limit (IIS 10 logs 413.1; older IIS logged 404.13)
       split("903 911 925", up, " ")
       for (j = 1; j <= 3; j++) line(up[j], "POST", "/api/upload", "-", "-", "10.20.1.33", web, "http://portal.example.com/docs", 413, 1, 0, 2)
       # someone trying the protected reports folder
       line(1501, "GET", "/reports/", "-", "-", "10.20.1.99", web, "-", 401, 2, 5, 1)
       line(1509, "GET", "/reports/", "-", "-", "10.20.1.99", web, "-", 401, 1, 1326, 12)
       line(1517, "GET", "/reports/", "-", "-", "10.20.1.99", web, "-", 401, 1, 1326, 11)
       line(1530, "GET", "/reports/", "-", "webadmin", "10.20.1.99", web, "-", 200, 0, 0, 18)
       line(1534, "GET", "/reports/nov.pdf", "-", "webadmin", "10.20.1.99", web, "-", 200, 0, 0, 40)
       # a scanner from the internet
       n = split("/web.config:404:8:0 /bin/app.dll:404:8:0 /backup.bak:404:7:0 /db.mdb:404:7:0 /.env:404:0:2 /wp-login.php:404:0:2 /phpmyadmin/:404:0:3 /.git/config:404:0:3 /admin.php:404:0:2 /server-status:404:0:2 /config.json:404:0:2 /test.aspx:404:0:2", sc, " ")
       for (j = 1; j <= n; j++) {
         split(sc[j], f, ":")
         line(2520 + j, "GET", f[1], "-", "-", "203.0.113.50", "Mozilla/5.0+zgrab/0.x", "-", f[2], f[3], f[4], 1)
       }
     }' > "$BODY"

{
  echo "#Software: Microsoft Internet Information Services 10.0"
  echo "#Version: 1.0"
  echo "#Date: 2026-11-11 04:30:00"
  echo "#Fields: date time s-ip cs-method cs-uri-stem cs-uri-query s-port cs-username c-ip cs(User-Agent) cs(Referer) sc-status sc-substatus sc-win32-status sc-bytes cs-bytes time-taken"
  LC_ALL=C sort -s -k1,2 "$BODY"
} > "$OUT"

echo "Created $OUT ($(grep -vc '^#' "$OUT") requests)"

# HTTPERR: what HTTP.sys rejected in the same hour, plus the pool failure that followed
ERR="$OUT_DIR/httperr1.log"
awk 'function ts(sec,   t) {
       t = 4 * 3600 + 30 * 60 + sec
       return sprintf("2026-11-11 %02d:%02d:%02d", int(t / 3600), int((t % 3600) / 60), t % 60)
     }
     function e(sec, cip, port, ver, method, uri, st, site, reason, queue) {
       printf "%s %s %d 10.0.0.5 80 %s %s %s - - %s %s %s %s TCP\n", ts(sec), cip, port, ver, method, uri, st, site, reason, queue
     }
     BEGIN {
       for (k = 0; k < 20; k++) e(60 + k * 170, "10.20.1." (10 + k * 3 % 40), 50100 + k, "-", "-", "-", "-", "-", "Timer_ConnectionIdle", "-")
       for (k = 0; k < 4; k++) e(1030 + k, "198.51.100.7", 61000 + k, "HTTP/1.1", "GET", "/", 404, "-", "NotFound", "-")
       for (k = 0; k < 8; k++) e(1745 + k * 55, "10.20.1." (11 + k * 5), 52000 + k, "HTTP/1.1", (k % 2 ? "GET" : "POST"), (k % 2 ? "/api/accounts" : "/api/transfer"), 503, 2, "QueueFull", "PortalPool")
       for (k = 0; k < 3; k++) e(3598 + k, "10.20.1." (20 + k), 53000 + k, "HTTP/1.1", "POST", "/api/transfer", "-", 2, "Connection_Abandoned_By_ReqQueue", "PortalPool")
       for (k = 0; k < 15; k++) e(3605 + k * 10, "10.20.1." (30 + k), 54000 + k, "HTTP/1.1", "GET", (k % 3 ? "/" : "/api/accounts"), 503, 2, "AppOffline", "PortalPool")
     }' > "$BODY"
{
  echo "#Software: Microsoft HTTP API 2.0"
  echo "#Version: 1.0"
  echo "#Date: 2026-11-11 04:30:00"
  echo "#Fields: date time c-ip c-port s-ip s-port cs-version cs-method cs-uri streamid streamid_ex sc-status s-siteid s-reason s-queuename transport"
  LC_ALL=C sort -s -k1,2 "$BODY"
} > "$ERR"

echo "Created $ERR ($(grep -vc '^#' "$ERR") lines)"
