# 00 · Setup: build the PayBank lab server

**Time:** 5 minutes · **Goal:** create `~/lab/srv`, a fake PayBank server with real-looking logs, configs and problems.

---

## 1 · Get the lab files onto your VM

The trainer gives you the folder `01-linux`. Copy it to your VM from your laptop:

```bash
scp -r 01-linux trainee01@[vm-ip]:~/
```

(No scp yet? The trainer can place it in your home folder. `scp` is taught in Topic 13.)

## 2 · Run the setup script

```bash
ssh trainee01@[vm-ip]
bash ~/01-linux/setup-lab.sh
```

## 3 · What you now have

```
~/lab/srv
├── backup/
│   └── portal.conf.bak              last known good Apache site file
├── etc/
│   ├── apache2/sites-available/
│   │   └── portal.conf              current site file (someone changed it!)
│   └── payment/
│       ├── app-prod.properties      production settings
│       └── app-staging.properties   staging settings
├── opt/tomcat/
│   ├── logs/
│   │   ├── catalina.out             app server log: the incident timeline
│   │   ├── catalina.2026-08-23.log  yesterday's log, 120 MB
│   │   └── heapdump-4123.hprof      memory dump, 60 MB
│   └── webapps/                     payment.war, portal.war
├── run/
│   └── payment.lock                 the file that blocks the restart
├── scripts/
│   └── rebuild_index.sh             a runaway CPU script (Topic 06)
└── var/log/
    ├── apache2/
    │   ├── access.log               30 requests, 09:01–09:16
    │   ├── access.log.1             yesterday, 12 MB
    │   └── error.log                Apache's errors
    └── payment/
        ├── gc.log                   2 MB
        └── archived/                six old .gz logs
```

## 4 · Check it worked

```bash
cd ~/lab/srv
wc -l var/log/apache2/access.log opt/tomcat/logs/catalina.out
du -sh ~/lab/srv
```

If `du` shows only a few KB, your file system does not support `fallocate`; Topic 07 numbers will look smaller but every command still works.

## Log formats you will read

**Apache access log** (combined format + response time in microseconds at the end):

```
10.0.0.21 - - [24/Aug/2026:09:04:00 +0530] "GET /payment/history?acct=1234 HTTP/1.1" 200 8921 "-" "Mozilla/5.0" 2501000
│                │                           │                                            │   │                     │
1 client IP      4 date/time                 6-8 request                                  9   10 bytes              last: µs
                                                                                       status
```

**App log** (`catalina.out`):

```
2026-08-24 09:13:14 FATAL [db-pool] Connection pool exhausted: maxTotal=20 active=20 waiting=31
│          │        │     │         │
date       time     level component message
```

Levels from least to most serious: `INFO` → `WARN` → `ERROR` → `FATAL`.
