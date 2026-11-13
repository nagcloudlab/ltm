# 13 · Advanced operations: appcmd scripting, live requests, memory recycling, custom log fields, log retention, delegation

**Time:** 60 min · **Advanced**

**You will learn:**
- script IIS with `appcmd` (find stopped pools and start them in one line)
- see the requests running **right now** and how long they have been running
- recycle a pool when it uses too much memory, and find the event
- log the real client address behind a load balancer (`X-Forwarded-For`)
- roll logs hourly and delete old logs automatically
- unlock a section so a site's `web.config` may change it (feature delegation)
- export a site's configuration

**Before you start:** topic 12 done (`/app`, `PortalAppPool`, `slow.aspx`).

---

## 13.1 · appcmd: list, filter, pipe

```powershell
Import-Module WebAdministration
Set-Alias appcmd "$env:windir\system32\inetsrv\appcmd.exe"
appcmd list site
appcmd list apppool
appcmd list apppool /state:Stopped
appcmd list site /state:Stopped
```

- `Set-Alias` lets you type `appcmd` instead of the long path, for this window only.
- `/state:Stopped` is a filter: only stopped objects are printed.

**Start every stopped pool in one line:**

```powershell
Stop-WebAppPool AdminPool
Start-Sleep -Seconds 5
appcmd list apppool /state:Stopped /xml | appcmd start apppool /in
appcmd list apppool
```

- `/xml` prints the objects as XML; `/in` makes the next `appcmd` read them. Like `xargs` on Linux.
- Expected: `"AdminPool" successfully started.` The pause lets the pool finish `Stopping` first; without it, `list /state:Stopped` finds nothing yet.

**Read one setting from every pool:**

```powershell
appcmd list apppool /text:name
appcmd list apppool /text:processModel.identityType
```

## 13.2 · Requests running right now

```powershell
Install-WindowsFeature Web-Request-Monitor
1..5 | ForEach-Object { Start-Process curl.exe -ArgumentList '-s -o NUL -H "Host: portal.example.com" http://localhost/app/slow.aspx' -WindowStyle Hidden }
Start-Sleep -Seconds 4
appcmd list requests
appcmd list requests /elapsed:3000
```

- `Start-Process` starts 5 `curl.exe` at the same time in the background.
- `list requests` shows each running request: URL, verb, the pipeline step it is in, and **time elapsed** (ms).

Sample line:

```text
REQUEST "a100000140000056" (url:GET /app/slow.aspx, time:4063 msec, client:localhost, stage:ExecuteRequestHandler, module:ManagedPipelineHandler)
```

- `stage:ExecuteRequestHandler, module:ManagedPipelineHandler` → the time is spent **inside the ASP.NET page**, not in IIS.
- `/elapsed:3000` = only requests running longer than 3 s: the first thing to run when "the site is hanging".
- IIS Manager: server → **Worker Processes** → double-click a pool → same list.

## 13.3 · Recycle on memory use

- A **memory leak** = the app keeps memory and never gives it back. Recycling on a memory limit is the safety net.

```powershell
Set-Content C:\inetpub\portal-app\memory.aspx '<%@ Page Language="C#" %><script runat="server">static System.Collections.Generic.List<byte[]> keep = new System.Collections.Generic.List<byte[]>();</script><% for (int i = 0; i < 30; i++) { keep.Add(new byte[10485760]); } %><p>holding <%= keep.Count * 10 %> MB</p>'
Set-ItemProperty IIS:\AppPools\PortalAppPool -Name recycling.periodicRestart.privateMemory -Value 204800
(Get-ItemProperty IIS:\AppPools\PortalAppPool -Name recycling.periodicRestart.privateMemory).Value
curl.exe -s -H "Host: portal.example.com" http://localhost/app/memory.aspx
curl.exe -s -H "Host: portal.example.com" http://localhost/app/hello.aspx
```

- `privateMemory` is in **KB**: `204800` = 200 MB. Each request to `memory.aspx` keeps 300 MB more.
- The pool recycles almost at once (on the test server: within a second). Ask `hello.aspx` again: it shows a **new Process ID**.

```powershell
curl.exe -s -H "Host: portal.example.com" http://localhost/app/hello.aspx
```

**Find the event:**

```powershell
Get-WinEvent -LogName System -MaxEvents 30 | Where-Object ProviderName -eq "Microsoft-Windows-WAS" | Format-Table TimeCreated, Id, Message -Wrap
```

- Look for WAS event **5117** (level Information): "A worker process serving application pool 'PortalAppPool' has requested a recycle because it reached its private bytes memory limit."
- Changing a pool setting also recycles it: event **5080** "… recycled due to 1 or more configuration changes".
- Other recycle reasons have their own WAS messages: time limit (`periodicRestart.time`), scheduled time, request limit, configuration change.
- On IIS 10 all recycle reasons are logged by default (`logEventOnRecycle`).

Put the limit back to "off":

```powershell
Set-ItemProperty IIS:\AppPools\PortalAppPool -Name recycling.periodicRestart.privateMemory -Value 0
Remove-Item C:\inetpub\portal-app\memory.aspx
Restart-WebAppPool PortalAppPool
```

## 13.4 · Log the real client behind a load balancer

```
Customer 49.37.10.5 ──► Load balancer 10.0.0.2 ──► IIS
                        adds header  X-Forwarded-For: 49.37.10.5
IIS c-ip column = 10.0.0.2  (the load balancer, every time)
```

- Add a **custom field** that copies the header into the log:

```powershell
Add-WebConfigurationProperty -PSPath IIS:\ -Filter "system.applicationHost/sites/site[@name='Portal']/logFile/customFields" -Name "." -Value @{ logFieldName = "X-Forwarded-For"; sourceName = "X-Forwarded-For"; sourceType = "RequestHeader" }
curl.exe -s -o NUL -H "Host: portal.example.com" -H "X-Forwarded-For: 49.37.10.5" http://localhost/
Get-ChildItem "C:\inetpub\logs\LogFiles\W3SVC$((Get-Website Portal).ID)"
```

- With a custom field, IIS starts a **second file** for the day: `u_exYYMMDD_x.log`. Its `#Fields:` line ends with `X-Forwarded-For`.
- These lines are written by IIS itself, up to about **a minute** later; `netsh http flush logbuffer` does not hurry them. Wait a minute, then read again:

```powershell
Start-Sleep -Seconds 70
Select-String -Path "C:\inetpub\logs\LogFiles\W3SVC$((Get-Website Portal).ID)\*_x.log" -Pattern "49.37.10.5" | ForEach-Object Line
```

Sample line:

```text
2026-11-13 05:40:04 ::1 GET / - 80 - ::1 curl/8.21.0 - 200 0 0 353 111 87 49.37.10.5
```

- The last field is the real customer address.

Remove the custom field again, so Portal logs to the normal file in the next topics:

```powershell
Remove-WebConfigurationProperty -PSPath IIS:\ -Filter "system.applicationHost/sites/site[@name='Portal']/logFile/customFields" -Name "." -AtElement @{logFieldName="X-Forwarded-For"}
```
- Requests without the header show `-` there.
- Same idea as Apache `%{X-Forwarded-For}i` and Nginx `$http_x_forwarded_for`.

## 13.5 · Log rollover and retention

```powershell
Get-ItemProperty "IIS:\Sites\Portal" -Name logFile | Select-Object period, truncateSize, directory
Set-ItemProperty "IIS:\Sites\Portal" -Name logFile.period -Value Hourly
```

| `period` | File name |
|---|---|
| `Daily` (default) | `u_exYYMMDD.log` |
| `Hourly` | `u_exYYMMDDHH.log` |
| `MaxSize` (with `truncateSize` in bytes) | `u_extendNN.log` |

- **IIS never deletes old logs.** A busy server fills its disk after some months: plan a clean-up.

**See what would be deleted (older than 30 days):**

```powershell
Get-ChildItem C:\inetpub\logs\LogFiles -Recurse -Filter *.log | Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) | Select-Object FullName, LastWriteTime
Get-ChildItem C:\inetpub\logs\LogFiles -Recurse -Filter *.log | Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) | Remove-Item -WhatIf
```

- `-WhatIf` only prints; nothing is deleted. Always run it first.

**Run it every night at 02:00 as a scheduled task:**

```powershell
$action = New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -Command "Get-ChildItem C:\inetpub\logs\LogFiles -Recurse -Filter *.log | Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) | Remove-Item"'
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -TaskName "IIS log cleanup" -Action $action -Trigger $trigger -User "NT AUTHORITY\SYSTEM"
Get-ScheduledTask -TaskName "IIS log cleanup"
Start-ScheduledTask -TaskName "IIS log cleanup"
```

- Linux equivalent: `logrotate` (Apache and Nginx get it automatically on Ubuntu).
- Put daily rollover back for the next topics:

```powershell
Set-ItemProperty "IIS:\Sites\Portal" -Name logFile.period -Value Daily
```

## 13.6 · Feature delegation: unlock a section

- In topic 05, authentication in a site's `web.config` gave **500.19** `0x80070021`: the section is **locked** at server level.
- The server admin can **unlock** it, so developers may set it in `web.config`:

```powershell
Copy-Item C:\inetpub\admin\web.config C:\inetpub\admin\web.config.keep -ErrorAction SilentlyContinue
appcmd unlock config -section:system.webServer/security/authentication/anonymousAuthentication
Set-Content C:\inetpub\admin\web.config '<configuration><system.webServer><security><authentication><anonymousAuthentication enabled="true" /></authentication></security></system.webServer></configuration>'
Start-Sleep -Seconds 2
curl.exe -s -o NUL -w "%{http_code}\n" http://localhost:8090/
appcmd lock config -section:system.webServer/security/authentication/anonymousAuthentication
Start-Sleep -Seconds 2
curl.exe -s -o NUL -w "%{http_code}\n" http://localhost:8090/
Remove-Item C:\inetpub\admin\web.config
Move-Item C:\inetpub\admin\web.config.keep C:\inetpub\admin\web.config -ErrorAction SilentlyContinue
```

- Unlocked: `200`. Locked again: `500` (500.19, `0x80070021`). The pauses give IIS time to read the new settings. Then the test file is removed and Admin's own `web.config` (if it had one) is put back.
- IIS Manager: server → **Feature Delegation** → Read/Write vs Read Only for each feature.
- Rule of thumb: keep security sections locked; unlock only what the developers really need.

## 13.7 · Export a site's configuration

```powershell
appcmd list site Portal /config /xml | Out-File C:\Users\Public\portal-site.xml
appcmd list apppool PortalPool /config /xml | Out-File C:\Users\Public\portalpool.xml
notepad C:\Users\Public\portal-site.xml
```

- The XML holds bindings, paths, applications, log settings: a record of the site, or a way to create the same site on a second server (`Get-Content portal-site.xml | appcmd add site /in`).

---

## Exercises

1. Print only the names of pools that run as `LocalSystem`.
2. A user says "the site hangs". Which command shows requests running longer than 10 s?
3. Set PortalPool to recycle at 200 MB private memory. Which unit, and which event tells you it happened?
4. The log shows the same `c-ip` for every request. Why, and what do you add?
5. Write the `-WhatIf` command that would delete Admin's logs older than 14 days.

## Answers

1. `appcmd list apppool /processModel.identityType:LocalSystem /text:name`.
2. `appcmd list requests /elapsed:10000`.
3. `Set-ItemProperty IIS:\AppPools\PortalPool -Name recycling.periodicRestart.privateMemory -Value 204800` (KB); WAS event 5117 (Information) in the System log, "reached its private bytes memory limit".
4. A load balancer or proxy is in front: add the `X-Forwarded-For` custom field (13.4).
5. `Get-ChildItem "C:\inetpub\logs\LogFiles\W3SVC$((Get-Website Admin).ID)" -Filter *.log | Where-Object LastWriteTime -lt (Get-Date).AddDays(-14) | Remove-Item -WhatIf`.
