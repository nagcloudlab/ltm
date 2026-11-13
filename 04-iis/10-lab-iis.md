# 10 · IIS lab: two sites, three faults, one log report

**Time:** 45 min · **Work:** in pairs · **Use:** topics 01–09

Windows VM with IIS, Portal (port 80, `portal.example.com`) and Admin (port 8090) from topics 02–03. Ubuntu VM for step 9. Do every step and write the evidence.

---

## Steps

| # | Task | Your evidence |
|---|---|---|
| 1 | **Healthy?** W3SVC and WAS running, both sites Started, both pools Started, who owns port 80 | |
| 2 | **Ask each site** `curl.exe -I` Portal and Admin; read the `Server:` header | |
| 3 | **Back up** the IIS config with appcmd; list the backup | |
| 4 | **Fault A** (your partner stops one pool without telling you): find which, and from which log | |
| 5 | **Fault B** (partner renames `index.html` in Admin): status.substatus and fix | |
| 6 | **Fault C** (partner adds a typo to Portal's web.config): error code, file, fix | |
| 7 | **Harden Admin:** anonymous off, Basic on; only `127.0.0.1` allowed; prove 401.2 and 200 | |
| 8 | **Hide and log:** remove `Server` and `X-Powered-By`; add `cs-host` to Portal's log fields; prove both | |
| 9 | **Log report** on Ubuntu from `u_ex261111.log`: total requests, top error, slowest URL, 500 window in IST | |
| 10 | **Restore** the backup from step 3 and prove Admin is anonymous again | |

---

## Commands (in order)

### 1

```powershell
Import-Module WebAdministration
Get-Service W3SVC, WAS
Get-Website
Get-ChildItem IIS:\AppPools | Where-Object Name -in "PortalPool","AdminPool" | Select-Object Name, State
Get-NetTCPConnection -LocalPort 80 -State Listen | Select-Object LocalAddress, OwningProcess
```

### 2

```powershell
curl.exe -I -H "Host: portal.example.com" http://localhost/
curl.exe -I http://localhost:8090/
```

### 3

```powershell
& $env:windir\system32\inetsrv\appcmd.exe add backup "lab-start"
& $env:windir\system32\inetsrv\appcmd.exe list backup
```

### 4 (partner breaks first)

Partner:

```powershell
Stop-WebAppPool AdminPool
```

You:

```powershell
curl.exe -i http://localhost:8090/
netsh http flush logbuffer
Get-Content C:\Windows\System32\LogFiles\HTTPERR\httperr*.log -Tail 3
Get-ChildItem IIS:\AppPools | Select-Object Name, State
Start-Sleep -Seconds 5
Start-WebAppPool AdminPool
Get-WebAppPoolState AdminPool
```

### 5

Partner:

```powershell
Rename-Item C:\inetpub\admin\index.html index.old
```

You:

```powershell
curl.exe -I http://localhost:8090/
netsh http flush logbuffer
Get-Content "C:\inetpub\logs\LogFiles\W3SVC$((Get-Website Admin).ID)\u_ex$((Get-Date).ToUniversalTime().ToString('yyMMdd')).log" -Tail 2
Get-ChildItem C:\inetpub\admin
Rename-Item C:\inetpub\admin\index.old index.html
```

### 6

Partner:

```powershell
Copy-Item C:\inetpub\portal\web.config C:\inetpub\portal\web.config.bak
(Get-Content C:\inetpub\portal\web.config) -replace "</system.webServer>", "</system.webserver>" | Set-Content C:\inetpub\portal\web.config
```

You (also open the page in a browser **on the server**):

```powershell
curl.exe -I -H "Host: portal.example.com" http://localhost/
Start-Process http://portal.example.com/
Copy-Item C:\inetpub\portal\web.config.bak C:\inetpub\portal\web.config -Force
curl.exe -I -H "Host: portal.example.com" http://localhost/
```

### 7

```powershell
Set-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/authentication/anonymousAuthentication -Name enabled -Value $false
Set-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/authentication/basicAuthentication -Name enabled -Value $true
Set-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/ipSecurity -Name allowUnlisted -Value $false
Add-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/ipSecurity -Name "." -Value @{ipAddress="127.0.0.1"; allowed="true"}
Add-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/ipSecurity -Name "." -Value @{ipAddress="::1"; allowed="true"}
curl.exe -I http://localhost:8090/
curl.exe -I -u webadmin:yourpassword http://localhost:8090/
```

Ask your partner to try `http://[win-ip]:8090/` from their machine.

### 8

```powershell
Set-WebConfigurationProperty -PSPath IIS:\ -Filter system.webServer/security/requestFiltering -Name removeServerHeader -Value $true
Remove-WebConfigurationProperty -PSPath IIS:\ -Filter system.webServer/httpProtocol/customHeaders -Name "." -AtElement @{name="X-Powered-By"} -ErrorAction SilentlyContinue
curl.exe -sI -H "Host: portal.example.com" http://localhost/ | Select-String "Server|X-Powered-By"
Set-ItemProperty "IIS:\Sites\Portal" -Name logFile.logExtFileFlags -Value "Date,Time,ClientIP,UserName,ServerIP,Method,UriStem,UriQuery,HttpStatus,Win32Status,BytesSent,BytesRecv,TimeTaken,ServerPort,UserAgent,Referer,HttpSubStatus,Host"
curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/
netsh http flush logbuffer
Get-Content "C:\inetpub\logs\LogFiles\W3SVC$((Get-Website Portal).ID)\u_ex$((Get-Date).ToUniversalTime().ToString('yyMMdd')).log" -Tail 3
```

### 9 (Ubuntu)

- Copy the script first, from PowerShell: `scp make-iis-sample-log.sh student@[ubuntu-ip]:~` (your user and address).

```bash
bash make-iis-sample-log.sh
cd ~/lab/iis
grep -vc '^#' u_ex261111.log
awk '!/^#/ && $12>=400 {print $12"."$13}' u_ex261111.log | sort | uniq -c | sort -rn | head -3
awk '!/^#/ {sum[$5]+=$17; n[$5]++} END {for (u in sum) printf "%8.0f ms  %s\n", sum[u]/n[u], u}' u_ex261111.log | sort -rn | head -3
awk '!/^#/ && $12==500 {print $1" "$2" UTC"}' u_ex261111.log | sed -n '1p;$p' | while read -r t; do TZ=Asia/Kolkata date -d "$t" '+%H:%M:%S IST'; done
```

### 10

```powershell
& $env:windir\system32\inetsrv\appcmd.exe restore backup "lab-start"
curl.exe -I http://localhost:8090/
```

---

## Fast finishers

1. Add `pay.example.com` to Portal without restarting anything; prove the old name still works, and find out which site answers a third name that has no binding.
2. Set up Failed Request Tracing for Portal for status `404`, request `/nothing.html`, and find the module that set the status in the trace.
3. Compare the IIS `Admin` site with Apache's password-protected site from `02-apache`: what is the same and what is different in how each one rejects an unknown user (status, header, log line)?

---

## Trainer answer key

| # | Expected evidence |
|---|---|
| 1 | both `Running`; Portal and Admin `Started`; both pools `Started`; port 80 `OwningProcess 4` (System = HTTP.sys) |
| 2 | `200`, `Server: Microsoft-IIS/10.0` for both |
| 3 | `BACKUP "lab-start"` in the list; folder `C:\Windows\System32\inetsrv\backup\lab-start` |
| 4 | `503`, `Server: Microsoft-HTTPAPI/2.0`; HTTPERR line `503 3 Disabled AdminPool` (`Disabled` = stopped by an admin); AdminPool `Stopped` |
| 5 | `403`; log `403 14 0`; folder has `index.old` only |
| 6 | `500`; browser: HTTP Error 500.19, Error Code `0x8007000d`, "Configuration file is not well-formed XML", Config File `…\portal\web.config`; log `500 19 13`; `200` after restore |
| 7 | `401` with `WWW-Authenticate: Basic`, log `401 2 5`; with credentials `200`, log shows `webadmin`; partner gets `403` (log `403 503 5`) |
| 8 | no `Server:` and no `X-Powered-By:` lines; new `#Fields:` line with `cs-host` just before `sc-status`; the newest line shows `portal.example.com` in that column |
| 9 | `260`; `404.0` (32, mostly `/favicon.ico`); `/api/transfer` ~7972 ms average; 500s from `10:26:15 IST` to `10:38:45 IST` |
| 10 | Admin anonymous again: `200` without credentials (ipSecurity and Basic rules gone) |
| FF 1 | `New-WebBinding -Name Portal -Port 80 -HostHeader pay.example.com`; both names give the Portal page; a third name gets the **Default Web Site** page (its `*:80:` binding catches every unknown name). Without that catch-all: `404` from `Microsoft-HTTPAPI/2.0` |
| FF 2 | Request Summary shows status `404` and the module that set it (for a missing static file: `IIS Web Core`, `HttpStatus 404`, `ErrorCode 0x80070002`, topic 06.9); Compact View lists every step with its time |
| FF 3 | both send `401` + `WWW-Authenticate: Basic realm=…`; IIS logs `401 2 5` (sub-status tells why); Apache's access.log shows only `401` |
