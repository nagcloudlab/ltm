# 01 · Install IIS and take a first look

**Time:** 35 min

**You will learn:** IIS in one picture, install it on Windows Server or Windows 10/11, the two services behind it, why port 80 belongs to "System", the default site, the IIS Manager window, where files and logs live, and starting/stopping.

---

## 01.1 · IIS in one picture

```
Visitor ──► HTTP.sys (Windows kernel, owns port 80)
                │  hands each request to the right application pool
                ▼
           w3wp.exe  (worker process of the site's pool)  ──reads──►  C:\inetpub\wwwroot\iisstart.htm
                │
                └── writes a line to C:\inetpub\logs\LogFiles\W3SVC1\u_exYYMMDD.log
```

| | Apache / Nginx | IIS |
|---|---|---|
| runs on | Linux (also Windows) | **Windows only** |
| port opened by | the web server's master process | **HTTP.sys**, a kernel driver |
| one website | VirtualHost / server block | **Site** |
| port + name | Listen + ServerName / listen + server_name | **Binding** |
| workers | www-data processes | **application pool** → `w3wp.exe` |
| config | text files in /etc | **IIS Manager** window → XML files |
| typical apps | PHP, static, reverse proxy | **.NET** (ASP.NET) |

## 01.2 · Install

### On Windows Server 2022

```powershell
Install-WindowsFeature -Name Web-Server, Web-Mgmt-Console, Web-Scripting-Tools -IncludeManagementTools
Get-WindowsFeature Web-* | Where-Object Installed | Select-Object Name, DisplayName
```

### On Windows 10 / 11 Pro

```powershell
Enable-WindowsOptionalFeature -Online -All -FeatureName IIS-WebServerRole, IIS-WebServer, IIS-ManagementConsole, IIS-ManagementScriptingTools
Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -like "IIS-*" -and $_.State -eq "Enabled" } | Select-Object FeatureName
```

(Or: Control Panel → Programs → Turn Windows features on or off → Internet Information Services.)

| Feature | Gives you |
|---|---|
| Web Server | the web server itself (static files, logging, request filtering) |
| Management Console | IIS Manager (`inetmgr`) |
| Scripting Tools | the PowerShell module `WebAdministration` |

Extra features (basic authentication, IP restrictions, tracing) are added in later topics, when needed.

## 01.3 · Prove it works

```powershell
Get-Service W3SVC, WAS
curl.exe -I http://localhost/
Start-Process http://localhost/
```

| Service | Name | Job |
|---|---|---|
| `W3SVC` | World Wide Web Publishing Service | the web server; configures HTTP.sys |
| `WAS` | Windows Process Activation Service | starts and watches the worker processes (pools) |

The browser shows the blue **Internet Information Services** welcome page: the file `C:\inetpub\wwwroot\iisstart.htm`.

```powershell
Get-ChildItem C:\inetpub\wwwroot
curl.exe -s -I http://localhost/ | Select-String "Server"
```

`Server: Microsoft-IIS/10.0`.

## 01.4 · Who owns port 80? "System"

```powershell
netstat -ano | findstr ":80 "
Get-Process -Id 4
Get-NetTCPConnection -LocalPort 80 -State Listen | Select-Object LocalAddress, LocalPort, OwningProcess
```

Port 80 belongs to **PID 4, "System"**: HTTP.sys, inside the kernel. This is normal and is the first surprise for Linux admins (`ss` would show `apache2`).

```powershell
netsh http show servicestate view=requestq | Select-String -Pattern "Request queue name|URL group|Registered URLs" -Context 0,1
```

Shows which URLs (sites and bindings) IIS registered with HTTP.sys.

## 01.5 · The worker process starts on demand

```powershell
Get-Process w3wp -ErrorAction SilentlyContinue
curl.exe -s -o NUL http://localhost/
Get-Process w3wp | Select-Object Id, StartTime
```

| Fact | Means |
|---|---|
| no `w3wp` until the first request | WAS starts it **on demand** |
| stops after 20 idle minutes (default) | the first visitor afterwards waits a little longer |
| one `w3wp` per pool | topic 03 |

```powershell
& $env:windir\system32\inetsrv\appcmd.exe list wp
```

`appcmd list wp` shows each worker process with the pool it serves.

## 01.6 · The IIS Manager window

```powershell
inetmgr
```

```
┌ Connections ──────────┐ ┌ Features (middle) ─────────────────────┐ ┌ Actions ──────────┐
│ ▾ WIN-LAB01           │ │ Authentication  Default Document        │ │ Explore           │
│   Application Pools   │ │ Directory Browsing  Error Pages         │ │ Edit Permissions… │
│   ▾ Sites             │ │ HTTP Response Headers  Logging          │ │ Bindings…         │
│     Default Web Site  │ │ MIME Types  Modules  Request Filtering  │ │ Basic Settings…   │
│                       │ │ Handler Mappings  Compression           │ │ Restart · Start   │
└───────────────────────┘ └─────────────────────────────────────────┘ │ Stop · Browse *:80│
                                                                       └───────────────────┘
```

| Click | Shows |
|---|---|
| the **server** name | server-wide features |
| **Application Pools** | pools, identities, Recycle, Start/Stop |
| a **site** | that site's features (they override server-wide ones) |
| **Bindings…** (Actions) | port and host names |
| **Basic Settings…** | physical path (= DocumentRoot) and pool |
| **Explore** | opens the site folder |

## 01.7 · Where things are

```powershell
Get-ChildItem C:\inetpub
Get-ChildItem C:\inetpub\logs\LogFiles
Get-Item C:\Windows\System32\inetsrv\config\applicationHost.config
```

| What | Windows / IIS | Linux / Apache |
|---|---|---|
| pages | `C:\inetpub\wwwroot\` | `/var/www/html/` |
| logs | `C:\inetpub\logs\LogFiles\W3SVC<site id>\` | `/var/log/apache2/` |
| server config | `C:\Windows\System32\inetsrv\config\applicationHost.config` | `/etc/apache2/` |
| per-site config | `web.config` in the site folder | `.htaccess` |
| tools | `C:\Windows\System32\inetsrv\` (`appcmd.exe`, `inetmgr.exe`) | `/usr/sbin/` |

## 01.8 · Start, stop, restart

| Scope | Command | Linux equivalent |
|---|---|---|
| one site | `Stop-Website "Default Web Site"` · `Start-Website …` | `a2dissite` + reload (roughly) |
| one pool | `Restart-WebAppPool DefaultAppPool` | reload one app |
| the web service | `Restart-Service W3SVC` | `systemctl restart apache2` |
| **everything** IIS | `iisreset` | — |

```powershell
Import-Module WebAdministration
Stop-Website "Default Web Site"
curl.exe -I http://localhost/
Start-Website "Default Web Site"
curl.exe -I http://localhost/
iisreset /status
```

- Stopped site, and no other site on port 80: HTTP.sys stops listening on 80, so curl cannot connect at all.
- Once another site still uses port 80 (from topic 02 on), HTTP.sys answers instead, with `Server: Microsoft-HTTPAPI/2.0`.
- Either way, IIS never saw the request.

Sample line (stopped Default Web Site on a fresh server):

```text
curl: (7) Failed to connect to localhost port 80 after 2562 ms: Could not connect to server
```

> `iisreset` restarts **every** site and pool on the server: the big hammer. Prefer recycling one pool or restarting one site.

---

## Exercises

1. Which two Windows services must run for IIS to serve pages? Show their state in one command.
2. Why does `netstat` show PID 4 on port 80, and what is PID 4?
3. Stop the Default Web Site. Which `Server:` header answers now, and why?
4. Where is the configuration that IIS Manager edits?
5. What starts `w3wp.exe`, and when?

## Answers

1. `Get-Service W3SVC, WAS`.
2. HTTP.sys, the kernel driver, owns the port; PID 4 is the **System** process.
3. None: on a fresh server curl prints `Failed to connect … Could not connect to server`, because no running site uses port 80 any more, so HTTP.sys stops listening. (With other sites on port 80, HTTP.sys answers itself with `Server: Microsoft-HTTPAPI/2.0`.)
4. `C:\Windows\System32\inetsrv\config\applicationHost.config` (plus each site's `web.config`).
5. WAS (Windows Process Activation Service), on the first request to that pool.
