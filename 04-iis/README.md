# 04 · IIS (Internet Information Services) · Hands-on handout

A detailed lab handout for Microsoft's web server. One topic per file, in teaching order. Read the explanation, type the commands, do the exercises.

**Before you start:** finish `02-apache` and `03-nginx`. IIS does the same job (listen, pick a site, send a file, log) with different words and a window instead of config files. Each topic shows the Apache/Nginx equivalent.

---

## Where you practise

IIS runs **only on Windows**.

| Option | Use |
|---|---|
| **Windows Server 2022 VM** (preferred) | closest to company servers |
| **Windows 10 / 11 Pro or Enterprise laptop** | works for every topic (Home edition has no IIS) |
| your **Ubuntu lab VM** | topic 07 only: analyse IIS logs with Linux tools |

Run **PowerShell as Administrator** for every command (Start → type PowerShell → right-click → Run as administrator).

---

## Topics

| # | File | Topic | Time |
|---|---|---|---|
| 01 | [01-install-and-first-look.md](01-install-and-first-look.md) | install, services (W3SVC, WAS), HTTP.sys, IIS Manager tour, folders | 35 min |
| 02 | [02-sites-and-bindings.md](02-sites-and-bindings.md) | sites, bindings (host name, port), hosts file, unknown host names | 40 min |
| 03 | [03-application-pools.md](03-application-pools.md) | pools, identities, NTFS permissions, recycling, idle timeout, rapid-fail, 503 | 45 min |
| 04 | [04-configuration.md](04-configuration.md) | applicationHost.config, web.config, default document, browsing, error pages, MIME, backups, 500.19 | 45 min |
| 05 | [05-security.md](05-security.md) | authentication (401), IP restrictions, request filtering (404.x), headers, redirects | 45 min |
| 06 | [06-logs-and-tracing.md](06-logs-and-tracing.md) | W3C logs, fields, UTC, buffering, HTTPERR, Event Viewer, Failed Request Tracing | 45 min |
| 07 | [07-log-analysis-on-linux.md](07-log-analysis-on-linux.md) | IIS logs on Ubuntu: grep, awk, sort, uniq, UTC → IST | 40 min |
| 08 | [08-performance.md](08-performance.md) | compression, client caching, queue length, performance counters, load test | 40 min |
| 09 | [09-troubleshooting.md](09-troubleshooting.md) | sub-status codes and eleven break-it cases | 60 min |
| 10 | [10-lab-iis.md](10-lab-iis.md) | **IIS lab:** two sites, three faults, one log report | 45 min |
| 11 | [11-https-and-certificates.md](11-https-and-certificates.md) | **Advanced:** certificate store, https binding, SNI, Require SSL (403.4), expiry check, Schannel events | 50 min |
| 12 | [12-applications-and-aspnet.md](12-applications-and-aspnet.md) | **Advanced:** applications, virtual directories, ASP.NET, handler mappings, slow and error pages | 50 min |
| 13 | [13-advanced-operations.md](13-advanced-operations.md) | **Advanced:** appcmd scripting, live requests, memory recycling, X-Forwarded-For, log retention, feature delegation | 60 min |
| 14 | [14-troubleshooting-scenarios.md](14-troubleshooting-scenarios.md) | **Advanced:** ten tickets: break, symptom, which log, sample line, cause, fix, verify | 90 min |
| 15 | [15-reading-logs.md](15-reading-logs.md) | **Advanced:** W3SVC and HTTPERR line by line, which log to open, drills on Ubuntu with answers | 60 min |
| 99 | [99-cheatsheet.md](99-cheatsheet.md) | one page, with Apache/Nginx equivalents | |
| — | [make-iis-sample-log.sh](make-iis-sample-log.sh) | creates `~/lab/iis/u_ex261111.log` and `~/lab/iis/httperr1.log` on Ubuntu (topics 07, 15) | |

---

## How to use the files

- **Command blocks contain only commands.** `powershell` blocks run in an **Administrator PowerShell** on Windows; `bash` blocks run on your Ubuntu VM.
- Blocks marked `xml` are config to put into a file.
- In PowerShell, always type **`curl.exe`**, not `curl`: in Windows PowerShell 5.1, `curl` is a different command (`Invoke-WebRequest`).
- Change routine: back up the config (topic 04) → change → test with `curl.exe` → read the log.
- **Break it** steps are deliberate mistakes. Do them, read the error, then fix.
- Each topic ends with **Exercises** and **Answers**.
- **Every new PowerShell window:** run `Import-Module WebAdministration` first. Without it, paths like `IIS:\Sites\Portal` do not exist yet.
- Topics 01–10 are the core course. Topics 11–15 are **advanced**: do them in order, after the lab.
- Anything that needs an **extra download** (URL Rewrite, ASP.NET Core Hosting Bundle) is marked as such; the labs never require it.

### Names used everywhere

| Item | Value |
|---|---|
| sites | `Portal` (`portal.example.com`, port 80), `Admin` (port 8090) |
| folders | `C:\inetpub\portal`, `C:\inetpub\admin` |
| pools | `PortalPool`, `AdminPool` (topic 12 adds `PortalAppPool`) |
| Windows machine | `[win-ip]` (find it with `ipconfig`) |
