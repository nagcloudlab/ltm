# IIS on one page (with Apache and Nginx equivalents)

Run in an **Administrator PowerShell** after `Import-Module WebAdministration`. Always `curl.exe`, never `curl`.

## Service and status
| IIS | Apache | Nginx |
|---|---|---|
| `Get-Service W3SVC, WAS` | `systemctl status apache2` | `systemctl status nginx` |
| `Restart-Service W3SVC` | `systemctl restart apache2` | `systemctl restart nginx` |
| `iisreset` (everything, avoid) · `iisreset /status` | | |
| `Restart-WebAppPool PortalPool` (one site's workers) | `systemctl reload apache2` | `systemctl reload nginx` |
| `Stop-Website Portal` · `Start-Website Portal` | `a2dissite` + reload | remove link + reload |
| `Get-NetTCPConnection -LocalPort 80 -State Listen` → PID 4 = HTTP.sys | `ss -lntp` → apache2 | `ss -lntp` → nginx |
| `appcmd list wp` · `Get-Process w3wp` | `ps -C apache2` | `ps -C nginx` |

## Files
| What | IIS | Apache / Nginx |
|---|---|---|
| server config | `C:\Windows\System32\inetsrv\config\applicationHost.config` | `/etc/apache2/` · `/etc/nginx/` |
| per-folder config | `web.config` | `.htaccess` · (none) |
| web root | `C:\inetpub\wwwroot`, `C:\inetpub\portal` | `/var/www/html` |
| site log | `C:\inetpub\logs\LogFiles\W3SVC<ID>\u_exYYMMDD.log` | `/var/log/apache2/access.log` · `/var/log/nginx/access.log` |
| kernel/front log | `C:\Windows\System32\LogFiles\HTTPERR\` | error.log |
| events | Event Viewer: System (WAS, W3SVC), Application | `journalctl -u …` |
| tools | `C:\Windows\System32\inetsrv\appcmd.exe`, `inetmgr` | `apache2ctl`, `nginx` |

## Change safely
`appcmd add backup "<name>"` → change (IIS Manager / PowerShell) → `curl.exe -I …` → `netsh http flush logbuffer` → read the log · undo: `appcmd restore backup "<name>"` · automatic copies in `C:\inetpub\history`

## Sites, bindings, pools
```powershell
New-WebAppPool PortalPool
New-Website -Name Portal -Port 80 -HostHeader portal.example.com -PhysicalPath C:\inetpub\portal -ApplicationPool PortalPool
New-WebBinding -Name Portal -Protocol http -Port 80 -HostHeader www.portal.example.com
Get-WebBinding | Select-Object protocol, bindingInformation
Get-ChildItem IIS:\AppPools | Select-Object Name, State
Get-WebAppPoolState PortalPool
icacls C:\inetpub\portal\uploads /grant "IIS AppPool\PortalPool:(OI)(CI)M"
```
Binding = `IP:port:hostname` (= `Listen` + `ServerName` / `listen` + `server_name`). Pool = worker processes `w3wp.exe`, identity `IIS AppPool\<pool>`. Defaults: recycle 1740 min, idle 20 min, queue 1000, rapid-fail 5 crashes in 5 min.

## Settings by command
```powershell
Get-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/directoryBrowse -Name enabled
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/directoryBrowse -Name enabled -Value $false
Set-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/authentication/basicAuthentication -Name enabled -Value $true
```
`-PSPath IIS:\` = server-wide · `-PSPath "IIS:\Sites\X"` = writes X's web.config · `-Location X` = stored in applicationHost.config (needed for locked sections such as authentication)

| Feature (Request path) | IIS section | Apache | Nginx |
|---|---|---|---|
| index file | `defaultDocument` | `DirectoryIndex` | `index` |
| listing | `directoryBrowse` | `Options Indexes` | `autoindex` |
| error page | `httpErrors` | `ErrorDocument` | `error_page` |
| file types | `staticContent` (mimeMap) | `mime.types` | `mime.types` |
| login | `security/authentication` | `AuthType Basic` | `auth_basic` |
| IP rules | `security/ipSecurity` | `Require ip` | `allow` / `deny` |
| size / URL limits | `security/requestFiltering` | `LimitRequestBody` | `client_max_body_size` |
| headers | `httpProtocol/customHeaders` | `Header set` | `add_header` |
| redirect | `httpRedirect` | `Redirect` | `return 301` |
| compression | `urlCompression` | `mod_deflate` | `gzip` |
| browser cache | `staticContent/clientCache` | `mod_expires` | `expires` |

## Logs
```text
#Fields: date time s-ip cs-method cs-uri-stem cs-uri-query s-port cs-username c-ip cs(User-Agent) cs(Referer) sc-status sc-substatus sc-win32-status sc-bytes cs-bytes time-taken
```
(the 17 default fields on Windows Server 2022)
Times **UTC** (IST = +5:30) · time-taken **ms** · status = awk `$12`, sub-status `$13`, win32 `$14`, sc-bytes `$15`, cs-bytes `$16`, time `$17` · buffered: `netsh http flush logbuffer`
```powershell
Get-Content <log> -Tail 20 -Wait
Select-String -Path <log> -Pattern " 500 "
Get-Content C:\Windows\System32\LogFiles\HTTPERR\httperr*.log -Tail 5
```
```bash
awk '!/^#/ {print $12"."$13}' u_ex261111.log | sort | uniq -c | sort -rn
awk '!/^#/' u_ex261111.log | sort -k17,17n | tail -5
```

## Status codes that matter
| Code | Means | Code | Means |
|---|---|---|---|
| 404 from `Microsoft-HTTPAPI/2.0` | no binding for that name (HTTPERR `NotFound`) | 404.3 | no MIME type |
| 401.1 / 401.2 | wrong password / no login | 404.7 / 404.8 | blocked extension / hidden folder |
| 401.3 | NTFS denies the file | 413.1 | upload too big (30,000,000 bytes; older IIS 404.13) |
| 403.14 | no default document | 404.14 / 404.15 / 404.20 | URL / query too long / too many URL parts |
| 403.503 | IP rejected | 500.19 | bad config: `0x8007000d` XML · `0x80070021` locked · `0x80070005` access |
| 404.0 | not found | 503 `Microsoft-HTTPAPI/2.0` | HTTPERR `Disabled` (admin stopped pool) · `AppOffline` (Rapid-Fail) · `QueueFull` |

## Troubleshoot in 7 steps
1 `curl.exe -i` → 2 which `Server:` → 3 site log status.substatus (flush) → 4 HTTPERR → 5 site and pool state → 6 Event Viewer (WAS 5009/5011/5002) → 7 detailed error on the server or Failed Request Tracing

## Advanced (topics 11–15)
`appcmd` below = after `Set-Alias appcmd "$env:windir\system32\inetsrv\appcmd.exe"`
```powershell
New-SelfSignedCertificate -DnsName portal.example.com -CertStoreLocation Cert:\LocalMachine\My
New-WebBinding -Name Portal -Protocol https -Port 443 -HostHeader portal.example.com -SslFlags 1
netsh http show sslcert
Get-ChildItem IIS:\SslBindings
New-WebVirtualDirectory -Site Portal -Name docs -PhysicalPath C:\paybank-docs
New-WebApplication -Site Portal -Name app -PhysicalPath C:\inetpub\portal-app -ApplicationPool PortalAppPool
appcmd list apppool /state:Stopped /xml | appcmd start apppool /in
appcmd list requests /elapsed:3000
Set-ItemProperty IIS:\AppPools\PortalAppPool -Name recycling.periodicRestart.privateMemory -Value 204800
appcmd unlock config -section:system.webServer/security/authentication/anonymousAuthentication
```
- HTTPERR fields: `date time c-ip c-port s-ip s-port cs-version cs-method cs-uri streamid streamid_ex sc-status s-siteid s-reason s-queuename transport` (awk: status `$12`, reason `$14`, queue `$15`)
- Ignore `Timer_ConnectionIdle`; act on `Disabled`, `AppOffline`, `QueueFull`, `Connection_Abandoned_By_ReqQueue`
- Events: WAS 5009 / 5011 crash · W3SVC 1004 + HttpEvent 15005 port taken · 5002 pool disabled · 5117 private-memory recycle · ASP.NET 1309 unhandled exception · Schannel 36871 / 36874 / 36887 TLS
- More codes: 403.4 SSL required · 404.17 dynamic content on static handler · 500.21 handler module missing
- Custom log field: `logFile/customFields` → `X-Forwarded-For` (RequestHeader) · IIS never deletes old logs: scheduled clean-up
