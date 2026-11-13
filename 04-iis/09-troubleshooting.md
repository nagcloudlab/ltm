# 09 · Troubleshooting: sub-status codes and break-it cases

**Time:** 60 min

**You will learn:** a fixed checklist for any IIS problem, the sub-status codes you will meet most, and eleven cases you break on purpose, then diagnose and fix exactly as you would at work.

Work in pairs: one breaks (with the **Break** block), the other diagnoses without looking, then fixes.

---

## 09.1 · The checklist

```
1. What does the client get?   curl.exe -i …       → status, Server header, body
2. Who answered?               Microsoft-IIS/10.0 = IIS · Microsoft-HTTPAPI/2.0 = HTTP.sys only
3. Site log                    W3SVC<ID> → status.substatus win32 time-taken   (flush first)
4. Not in site log?            HTTPERR → s-reason
5. Pool and site state         Get-WebAppPoolState · Get-Website
6. Events                      System log: WAS, W3SVC · Application log
7. Detailed error              browser on the server, or Failed Request Tracing
```

Commands for the checklist, ready to paste:

```powershell
Import-Module WebAdministration
Get-Website | Select-Object Name, ID, State, PhysicalPath, ApplicationPool
Get-ChildItem IIS:\AppPools | Select-Object Name, State
netsh http flush logbuffer
Get-Content "C:\inetpub\logs\LogFiles\W3SVC$((Get-Website Portal).ID)\u_ex$((Get-Date).ToUniversalTime().ToString('yyMMdd')).log" -Tail 5
Get-ChildItem C:\Windows\System32\LogFiles\HTTPERR | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content -Tail 5
Get-WinEvent -LogName System -MaxEvents 30 | Where-Object { $_.ProviderName -match "WAS|W3SVC" } | Format-Table TimeCreated, Id, Message -Wrap
```

## 09.2 · The sub-status codes you will meet

| Code | Means | First check |
|---|---|---|
| 404 from `Microsoft-HTTPAPI/2.0` | no binding for this Host name (HTTPERR `NotFound`; older Windows: 400 Invalid Hostname) | bindings, DNS / hosts file |
| 401.1 | wrong user name or password | the account |
| 401.2 | no credentials sent / no auth method allowed | Authentication settings |
| 401.3 | NTFS denies the file | `icacls` |
| 403.14 | folder, no default document, browsing off | default document list |
| 403.503 | IP address rejected | IP and domain restrictions |
| 404.0 | file not found | physical path, file name |
| 404.3 | no MIME type for the extension | MIME Types |
| 404.7 / 404.8 | extension blocked / hidden segment | Request Filtering (usually correct) |
| 413.1 | body over `maxAllowedContentLength` (older IIS: 404.13) | Request Filtering limits |
| 404.14 / 404.15 / 404.20 | URL / query string too long / too many URL parts | Request Filtering limits |
| 500.0 | the application threw an error | app logs, developers |
| 500.19 | config invalid: `0x8007000d` XML, `0x80070021` locked, `0x80070005` access | the named config file and line |
| 502.3 | bad gateway from a proxy (ARR / ASP.NET Core) | the back end |
| 503 (HTTP.sys) | pool stopped (`Disabled` by an admin, `AppOffline` after crashes) or queue full (`QueueFull`) | HTTPERR, pool state, WAS events |

---

## Case 1 · Pool stopped

**Break**

```powershell
Stop-WebAppPool PortalPool
```

**Symptom:** `curl.exe -i -H "Host: portal.example.com" http://localhost/` → `503`, `Server: Microsoft-HTTPAPI/2.0`.

**Diagnose**

```powershell
Get-WebAppPoolState PortalPool
netsh http flush logbuffer
Get-Content C:\Windows\System32\LogFiles\HTTPERR\httperr*.log -Tail 3
```

Nothing in W3SVC log; HTTPERR shows `503 2 Disabled PortalPool`.

**Fix** (wait a few seconds after stopping, or the start fails with `0x80070425`)

```powershell
Start-WebAppPool PortalPool
```

## Case 2 · Pool keeps stopping (Rapid-Fail)

**Break:** run the kill loop from topic 03.8.

**Diagnose**

```powershell
Get-WinEvent -LogName System -MaxEvents 20 | Where-Object ProviderName -eq "Microsoft-Windows-WAS" | Format-Table TimeCreated, Id, Message -Wrap
```

Five crash events (5009 or 5011), then 5002: the pool was disabled. HTTPERR now says `AppOffline` instead of `Disabled`.

**Fix:** find why w3wp crashed (Application log, developers), then `Start-WebAppPool PortalPool`.

## Case 3 · Port already in use: the site will not start

**Break**

```powershell
Stop-Website Admin
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, 8090)
$listener.Start()
Start-Website Admin
```

**Symptom:** `Start-Website` fails: *"The process cannot access the file because it is being used by another process. (0x80070020)"*. IIS Manager: "The process cannot access the file…" when starting the site.

**Diagnose**

```powershell
Get-NetTCPConnection -LocalPort 8090 -State Listen | Select-Object LocalAddress, LocalPort, OwningProcess
Get-Process -Id (Get-NetTCPConnection -LocalPort 8090 -State Listen).OwningProcess
```

- The owner is `powershell` (or `pwsh`), not PID 4 (HTTP.sys): another program has the port.
- Linux equivalent: Apache's "Address already in use".

The System log tells the same story:

```powershell
Get-WinEvent -LogName System -MaxEvents 10 | Where-Object ProviderName -match "W3SVC|HttpEvent" | Format-Table TimeCreated, ProviderName, Id, Message -Wrap
```

- `HttpEvent 15005` → "Unable to bind to the underlying transport for [::]:8090".
- `IIS-W3SVC 1004` → "did not register the URL prefix http://*:8090/ for site 3. The site has been disabled"

**Fix**

```powershell
$listener.Stop()
Start-Website Admin
```

## Case 4 · Typo in web.config: 500.19

**Break**

```powershell
Copy-Item C:\inetpub\portal\web.config C:\inetpub\portal\web.config.bak
(Get-Content C:\inetpub\portal\web.config) -replace "</system.webServer>", "</system.webserver>" | Set-Content C:\inetpub\portal\web.config
```

**Symptom:** every page of Portal → `500`. Log: `500 19 13` (win32 13 = "the data is invalid").

**Diagnose:** open `http://portal.example.com/` in a browser **on the server**: Error Code `0x8007000d`, Config File `\\?\C:\inetpub\portal\web.config`, and the bad line. XML names are case-sensitive.

**Fix**

```powershell
Copy-Item C:\inetpub\portal\web.config.bak C:\inetpub\portal\web.config -Force
```

## Case 5 · Section locked: 500.19 `0x80070021`

**Break**

```powershell
Copy-Item C:\inetpub\admin\web.config C:\inetpub\admin\web.config.bak -ErrorAction SilentlyContinue
Set-Content C:\inetpub\admin\web.config '<configuration><system.webServer><security><authentication><anonymousAuthentication enabled="true" /></authentication></security></system.webServer></configuration>'
```

**Symptom:** `curl.exe -I http://localhost:8090/` → `500`. Log: `500 19 33` (33 = 0x21, "locked").

**Diagnose:** detailed page: Error Code `0x80070021`, *"This configuration section cannot be used at this path… locked… overrideModeDefault=Deny"*.

**Fix:** remove the section from web.config and set it with `-PSPath IIS:\ -Location Admin` (topic 05.2):

```powershell
Remove-Item C:\inetpub\admin\web.config
Copy-Item C:\inetpub\admin\web.config.bak C:\inetpub\admin\web.config -ErrorAction SilentlyContinue
```

## Case 6 · No default document: 403.14

**Break**

```powershell
Rename-Item C:\inetpub\portal\index.html index.old
```

**Symptom:** `/` → `403`. Log: `403 14 0`.

**Diagnose**

```powershell
Get-ChildItem C:\inetpub\portal
Get-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/defaultDocument/files/add -Name value | Select-Object Value
```

**Fix:** put the file back, or add the right name to the default documents. **Do not** turn on directory browsing to "fix" it.

```powershell
Rename-Item C:\inetpub\portal\index.old index.html
```

## Case 7 · NTFS permissions: 401.3

**Break**

```powershell
icacls C:\inetpub\portal\index.html /inheritance:r /grant "Administrators:F"
```

**Symptom:** `/` → `401`, log `401 3 5` (win32 5 = access denied).

**Diagnose**

```powershell
icacls C:\inetpub\portal\index.html
```

No `IUSR`, no `IIS_IUSRS`, no `IIS AppPool\PortalPool`.

**Fix**

```powershell
icacls C:\inetpub\portal\index.html /reset
```

## Case 8 · Missing MIME type: 404.3

**Break**

```powershell
Set-Content C:\inetpub\portal\app.webmanifest '{ "name": "PayBank" }'
Remove-WebConfigurationProperty -PSPath IIS:\ -Filter system.webServer/staticContent -Name "." -AtElement @{fileExtension=".webmanifest"} -ErrorAction SilentlyContinue
```

**Symptom:** `/app.webmanifest` → `404` although the file exists. Log: `404 3 50`.

**Diagnose:** `Test-Path C:\inetpub\portal\app.webmanifest` is True; sub-status 3 = MIME map.

**Fix**

```powershell
Add-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/staticContent -Name "." -Value @{fileExtension=".webmanifest"; mimeType="application/manifest+json"}
```

## Case 9 · Wrong Host name: 404 from HTTP.sys

**Break:** take away the catch-all, then call a name no binding has.

```powershell
& $env:windir\system32\inetsrv\appcmd.exe set site /site.name:"Default Web Site" /bindings:http/*:80:localhost
Start-Sleep -Seconds 2
curl.exe -i -H "Host: shop.portal.example.com" http://localhost/
```

**Symptom:** `HTTP/1.1 404 Not Found`, `Server: Microsoft-HTTPAPI/2.0`, body *"HTTP Error 404. The requested resource is not found."* (older Windows: `400 Bad Request - Invalid Hostname`).

**Diagnose**

```powershell
Get-WebBinding | Select-Object protocol, bindingInformation
netsh http flush logbuffer
Get-Content C:\Windows\System32\LogFiles\HTTPERR\httperr*.log -Tail 3
```

No binding for `shop.portal.example.com`; HTTPERR line `404 - NotFound` (no site ID: no site matched); nothing in any site log.

**Fix:** add the name to the site that should answer, and put the catch-all back:

```powershell
New-WebBinding -Name Portal -Protocol http -Port 80 -HostHeader shop.portal.example.com
& $env:windir\system32\inetsrv\appcmd.exe set site /site.name:"Default Web Site" /bindings:http/*:80:
curl.exe -I -H "Host: shop.portal.example.com" http://localhost/
```

## Case 10 · Upload too big: 413.1

**Break:** put Portal back to the default limit (30 MB; you raised it to 100 MB in 05.5), then upload 35 MB.

```powershell
Clear-WebConfiguration -PSPath "IIS:\Sites\Portal" -Filter system.webServer/security/requestFiltering/requestLimits
fsutil file createnew $env:TEMP\scan.pdf 35000000
curl.exe -s -o NUL -w "%{http_code}\n" -X POST --data-binary "@$env:TEMP\scan.pdf" -H "Host: portal.example.com" http://localhost/
```

**Symptom:** `413` (Request Entity Too Large). Log: `413 1 0` with `cs-bytes` of only a few hundred: IIS refused before reading the body. Older IIS: `404 13 0`.

**Fix** (if the business agrees, e.g. 50 MB):

```powershell
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/security/requestFiltering/requestLimits -Name maxAllowedContentLength -Value 52428800
```

## Case 11 · Wrong physical path: 404.0 everywhere, or 500.19 `0x80070003`

**Break**

```powershell
Set-ItemProperty "IIS:\Sites\Portal" -Name physicalPath -Value C:\inetpub\portl
```

**Symptom:** Portal → `500` with sub-status 19 and `0x80070003` (*"Cannot read configuration file"*, the folder does not exist), or `404.0` if the folder exists but is empty.

**Diagnose**

```powershell
(Get-Website Portal).PhysicalPath
Test-Path (Get-Website Portal).PhysicalPath
```

**Fix**

```powershell
Set-ItemProperty "IIS:\Sites\Portal" -Name physicalPath -Value C:\inetpub\portal
```

---

## Exercises

1. A site gives `503` with `Server: Microsoft-HTTPAPI/2.0`. Name two possible HTTPERR reasons and the check for each.
2. `500.19` with `0x80070021` after a developer added authentication settings to web.config. Explain and fix.
3. A `.woff2` font returns 404 although the file exists. Which sub-status do you expect, and the fix?
4. `Start-Website` fails with `0x80070020`. What do you run first?
5. Write the 7-step checklist from memory.

## Answers

1. `Disabled` / `AppOffline` (pool stopped by an admin / by Rapid-Fail: `Get-WebAppPoolState`, WAS events) and `QueueFull` (pool too slow: counters, `time-taken`).
2. Authentication sections are locked at server level; move the setting to applicationHost.config with `-Location <site>` and remove it from web.config.
3. 404.3; add a MIME type `.woff2` → `font/woff2`. (Windows Server 2022 already maps `.woff2` to `application/font-woff2`; older servers do not.)
4. `Get-NetTCPConnection -LocalPort <port> -State Listen` and `Get-Process -Id <OwningProcess>`; the System log shows HttpEvent 15005 and W3SVC 1004.
5. 09.1.
