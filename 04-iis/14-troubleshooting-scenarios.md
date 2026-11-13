# 14 · Troubleshooting scenarios: from the ticket to the fix

**Time:** 90 min · **Advanced** · **Work:** in pairs

**You will learn:**
- start from a user's complaint, not from the answer
- pick the right log first time, read the exact line, and explain each part
- fix, then **prove** the fix

**How to work:**
- One partner runs **Break** without showing the screen, then reads out only the **Ticket**.
- The other uses only the checklist from 09.1 and this topic's **Look here** commands.
- Swap after every scenario.

**Before you start:** topics 01–13 done (Portal with `/app`, `slow.aspx`, `error.aspx`; Admin on 8090; HTTPS from topic 11).

Helper for every scenario (run once per PowerShell window):

```powershell
Import-Module WebAdministration
Set-Alias appcmd "$env:windir\system32\inetsrv\appcmd.exe"
function Show-SiteLog($site, $n = 5) { netsh http flush logbuffer | Out-Null; Get-Content "C:\inetpub\logs\LogFiles\W3SVC$((Get-Website $site).ID)\u_ex$((Get-Date).ToUniversalTime().ToString('yyMMdd')).log" -Tail $n }
function Show-HttpErr($n = 5) { netsh http flush logbuffer | Out-Null; Get-ChildItem C:\Windows\System32\LogFiles\HTTPERR | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content -Tail $n }
```

- `Show-SiteLog Portal` = newest lines of Portal's log; `Show-HttpErr` = newest HTTPERR lines. Both flush the buffer first.

---

## Scenario 1 · "The app section is down, the rest of the portal works"

**Break**

```powershell
1..5 | ForEach-Object { curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/app/hello.aspx; Start-Sleep 2; Get-CimInstance Win32_Process -Filter "Name='w3wp.exe'" | Where-Object CommandLine -match "PortalAppPool" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force } }
```

**Ticket:** "Since a few minutes, `/app/` shows *Service Unavailable*. The home page is fine."

**Look here**

```powershell
curl.exe -i -H "Host: portal.example.com" http://localhost/app/hello.aspx
Show-HttpErr
Get-WebAppPoolState PortalAppPool
Get-WinEvent -LogName System -MaxEvents 20 | Where-Object ProviderName -eq "Microsoft-Windows-WAS" | Format-Table TimeCreated, Id, Message -Wrap
```

Sample line (HTTPERR):

```text
2026-11-13 06:12:40 ::1%0 50544 ::1%0 80 HTTP/1.1 GET /app/hello.aspx - - 503 2 AppOffline PortalAppPool TCP
```

- `Server: Microsoft-HTTPAPI/2.0` in the response → IIS never saw the request.
- `AppOffline PortalAppPool` → that pool was taken offline after errors (an admin stop would say `Disabled`); `/` uses PortalPool, so it still works.
- WAS **5009** / **5011** five times (worker died), then **5002** (pool disabled by Rapid-Fail).

**Cause:** the worker process crashed 5 times in 5 minutes; Rapid-Fail Protection stopped the pool.

**Fix**

```powershell
Start-WebAppPool PortalAppPool
```

**Verify**

```powershell
curl.exe -s -o NUL -w "%{http_code}\n" -H "Host: portal.example.com" http://localhost/app/hello.aspx
```

- At work: before starting the pool, find **why** it crashed (Application log, developers), or it will stop again.

---

## Scenario 2 · "Transfers are very slow"

**Break**

```powershell
1..6 | ForEach-Object { Start-Process curl.exe -ArgumentList '-s -o NUL -H "Host: portal.example.com" http://localhost/app/slow.aspx' -WindowStyle Hidden }
```

**Ticket:** "Pages under `/app/` take ages, sometimes 10 seconds."

**Look here** (while it is happening, then after)

```powershell
Start-Sleep -Seconds 3
appcmd list requests /elapsed:2000
Start-Sleep -Seconds 8
Show-SiteLog Portal 10
```

- The first pause lets the requests run for a while; the second lets them finish, so they reach the log.

Sample line (W3SVC):

```text
2026-11-13 06:20:31 ::1 GET /app/slow.aspx - 80 - ::1 curl/8.21.0 - 200 0 0 412 97 8031
```

- `appcmd list requests` shows several `/app/slow.aspx` requests with growing **time elapsed**: they are stuck inside the app.
- In the log: `200 0 0` = "success", but `time-taken` `8031` ms. **A 200 can still be a problem.**
- Only `/app/slow.aspx` is slow; static files are fast → the delay is in the app code (in real life: a database or another service).

**Cause:** the page waits 8 seconds before answering (in real life: a slow back end).

**Fix:** not an IIS setting. Give the developers the URL, the times, and the `time-taken` numbers. Do **not** just raise `queueLength` or restart the pool: the next requests will be slow again.

**Verify:** after the developers' fix, `time-taken` for that URL drops (topic 07 / 15 commands on the copied log).

---

## Scenario 3 · "The portal shows an error after the release"

**Break**

```powershell
Copy-Item C:\inetpub\portal\web.config C:\inetpub\portal\web.config.release
$cfg = Get-Content C:\inetpub\portal\web.config -Raw
$cfg -replace "</system.webServer>", "<rewrite><rules><rule name='https'><match url='(.*)' /><action type='Redirect' url='https://{HTTP_HOST}/{R:1}' /></rule></rules></rewrite></system.webServer>" | Set-Content C:\inetpub\portal\web.config
```

**Ticket:** "Since this morning's release every page of the portal says *500 Internal Server Error*."

**Look here**

```powershell
curl.exe -s -o NUL -w "%{http_code}\n" -H "Host: portal.example.com" http://localhost/
Show-SiteLog Portal 3
Start-Process http://portal.example.com/
```

Sample line (W3SVC):

```text
2026-11-13 06:31:02 ::1 GET / - 80 - ::1 curl/8.21.0 - 500 19 13 4825 82 3
```

- `500 19` → configuration error; win32 `13` = "the data is invalid".
- The detailed page on the server: **HTTP Error 500.19**, Error Code `0x8007000d`, Config File `…\portal\web.config`.
- The **Config Error** line is **empty**, and Config Source shows only `-1:` / `0:`. A 500.19 with an empty Config Error usually means web.config uses a section for a **module that is not installed**. Look for unusual sections (`<rewrite>`) in the file.

**Cause:** the release added URL Rewrite rules, but the **URL Rewrite** module (extra download) is not installed on this server.

**Fix:** either install URL Rewrite (the change request should have said so), or roll back the web.config:

```powershell
Copy-Item C:\inetpub\portal\web.config.release C:\inetpub\portal\web.config -Force
```

**Verify**

```powershell
curl.exe -s -o NUL -w "%{http_code}\n" -H "Host: portal.example.com" http://localhost/
```

---

## Scenario 4 · "One report gives 401, others are fine"

**Break**

```powershell
New-Item -ItemType Directory C:\inetpub\portal\reports -Force
Set-Content C:\inetpub\portal\reports\q3.html "<h1>Q3 report</h1>"
Set-Content C:\inetpub\portal\reports\q4.html "<h1>Q4 report</h1>"
icacls C:\inetpub\portal\reports\q4.html /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
```

**Ticket:** "`/reports/q3.html` opens; `/reports/q4.html` says *401 Unauthorized*. We never had a login on the portal."

**Look here**

```powershell
curl.exe -s -o NUL -w "%{http_code}\n" -H "Host: portal.example.com" http://localhost/reports/q4.html
Show-SiteLog Portal 2
icacls C:\inetpub\portal\reports\q3.html
icacls C:\inetpub\portal\reports\q4.html
```

Sample line (W3SVC):

```text
2026-11-13 06:40:12 ::1 GET /reports/q4.html - 80 - ::1 curl/8.21.0 - 401 3 5 6192 97 1
```

- `401 3` → access denied by the file's **ACL** (permissions), not a login problem.
- win32 `5` = "access denied".
- `icacls q3.html` lists inherited `BUILTIN\Users`, `IIS_IUSRS`; `q4.html` has only Administrators and SYSTEM, no `(I)` = inheritance removed.

**Cause:** the file lost its inherited permissions (typical after copying with a tool that keeps the source ACLs).

**Fix**

```powershell
icacls C:\inetpub\portal\reports\q4.html /reset
```

**Verify**

```powershell
curl.exe -s -o NUL -w "%{http_code}\n" -H "Host: portal.example.com" http://localhost/reports/q4.html
```

---

## Scenario 5 · "Users who type the IP address get Not Found"

**Break**

```powershell
appcmd set site /site.name:"Default Web Site" /bindings:http/*:80:localhost
```

**Ticket:** "Opening `http://<server IP>/` shows a plain *Not Found* page. Yesterday it showed the IIS page."

**Look here**

```powershell
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1).IPAddress
curl.exe -i "http://$ip/"
Show-HttpErr 3
Get-WebBinding | Select-Object ItemXPath, protocol, bindingInformation
```

Sample line (HTTPERR):

```text
2026-11-13 01:15:51 10.160.0.2 49927 10.160.0.2 80 HTTP/1.1 GET / - - 404 - NotFound - TCP
```

- `404 - NotFound -` → no site ID (`-`): HTTP.sys found **no binding** for that Host header (older Windows: `400 … Hostname`, "Bad Request - Invalid Hostname").
- `Get-WebBinding`: no binding with an empty host name on port 80 any more.

**Cause:** someone gave the catch-all site a host name.

**Fix**

```powershell
appcmd set site /site.name:"Default Web Site" /bindings:http/*:80:
```

**Verify**

```powershell
curl.exe -s -o NUL -w "%{http_code}\n" "http://$ip/"
```

---

## Scenario 6 · "Admin site will not start after a server change"

**Break**

```powershell
Stop-Website Admin
$squatter = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, 8090)
$squatter.Start()
```

**Ticket:** "After maintenance, the admin site is stopped and the Start button gives an error."

**Look here**

```powershell
Start-Website Admin
Get-NetTCPConnection -LocalPort 8090 -State Listen | Select-Object LocalAddress, OwningProcess
Get-Process -Id (Get-NetTCPConnection -LocalPort 8090 -State Listen).OwningProcess | Select-Object Id, ProcessName, Path
Get-WinEvent -LogName System -MaxEvents 10 | Where-Object ProviderName -eq "Microsoft-Windows-IIS-W3SVC" | Format-Table TimeCreated, Id, Message -Wrap
```

- `Start-Website` error: `0x80070020` = "the process cannot access the file because it is being used by another process" = **port taken**.
- The owner of 8090 is `powershell`, not PID 4 (HTTP.sys).
- W3SVC may log a warning that the site could not register its binding.

**Cause:** another program listens on 8090 (in real life: a monitoring agent, a second web server, a developer tool).

**Fix**

```powershell
$squatter.Stop()
Start-Website Admin
```

**Verify**

```powershell
curl.exe -s -o NUL -w "%{http_code}\n" http://localhost:8090/
```

---

## Scenario 7 · "Big documents cannot be uploaded"

**Break:** nothing; the default limit is the problem.

**Ticket:** "Uploading a 35 MB scan fails with *413 Request Entity Too Large*. Small files work."

**Look here**

```powershell
fsutil file createnew $env:TEMP\scan35.pdf 35000000
curl.exe -s -o NUL -w "%{http_code}\n" -X POST --data-binary "@$env:TEMP\scan35.pdf" -H "Host: portal.example.com" http://localhost/app/hello.aspx
Show-SiteLog Portal 2
Get-WebConfigurationProperty -PSPath "IIS:\Sites\Portal\app" -Filter system.webServer/security/requestFiltering/requestLimits -Name maxAllowedContentLength
```

Sample line (W3SVC):

```text
2026-11-13 07:02:10 ::1 POST /app/hello.aspx - 80 - ::1 curl/8.21.0 - 413 1 0 5239 191 3
```

- `413 1` → Request Filtering: body larger than `maxAllowedContentLength` (30,000,000 bytes). Older IIS: `404 13`.
- `191` bytes received → only the headers: IIS refused before the body.
- `3` ms → refused at once.

**Cause:** the IIS default upload limit (~28.6 MB).

**Fix** (50 MB, if the business agrees):

```powershell
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal\app" -Filter system.webServer/security/requestFiltering/requestLimits -Name maxAllowedContentLength -Value 52428800
```

**Verify**

```powershell
curl.exe -s -o NUL -w "%{http_code}\n" -X POST --data-binary "@$env:TEMP\scan35.pdf" -H "Host: portal.example.com" http://localhost/app/hello.aspx
```

- Now the request gets past IIS and reaches ASP.NET, which has its **own** limit (`maxRequestLength`, 4 MB by default): the answer changes from `413` to a `500` (log `500 0 0`), with ASP.NET event **1309** ("Event code: 3004 … Post size exceeded allowed limits", exception "Maximum request length exceeded").
- A real upload fix changes **both** limits (IIS in bytes, ASP.NET in KB).

---

## Scenario 8 · "The app throws errors for some customers"

**Break**

```powershell
1..3 | ForEach-Object { curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/app/error.aspx }
```

**Ticket:** "Customers see *Runtime Error* on the payment page."

**Look here**

```powershell
Show-SiteLog Portal 3
Get-WinEvent -LogName Application -MaxEvents 10 | Where-Object ProviderName -like "ASP.NET*" | Select-Object -First 1 | Format-List TimeCreated, Id, Message
```

Sample line (W3SVC):

```text
2026-11-13 07:10:05 ::1 GET /app/error.aspx - 80 - ::1 curl/8.21.0 - 500 0 0 3420 98 15
```

- `500 0 0` → the **application** failed (sub-status 0, win32 0). IIS itself is fine.
- Application log, source ASP.NET 4.x, event **1309**: `Exception type: InvalidOperationException`, `Exception message: Database connection pool exhausted`, plus the URL and the process.

**Cause:** an unhandled exception in the code.

**Fix:** hand the event text to the developers. IIS admin action: none, except checking the back end named in the message (here: the database pool).

**Verify:** after the code fix, the same URL gives `200` and no new 1309 events.

---

## Scenario 9 · "Certificate check says CERT MISSING"

**Break**

```powershell
$old = (Get-ChildItem IIS:\SslBindings | Where-Object Host -eq "portal.example.com").Thumbprint
Get-ChildItem Cert:\LocalMachine\My\$old | Export-Certificate -FilePath C:\Users\Public\portal-backup.cer
Get-ChildItem Cert:\LocalMachine\My\$old | Remove-Item
```

**Ticket:** "The certificate team 'cleaned up old certificates'. The nightly check (topic 11.9) now prints `CERT MISSING` for portal. The site still opens."

**Look here**

```powershell
curl.exe -k -s -o NUL -w "%{http_code}\n" https://portal.example.com/
Get-ChildItem IIS:\SslBindings | ForEach-Object {
    $c = Get-Item "Cert:\LocalMachine\My\$($_.Thumbprint)" -ErrorAction SilentlyContinue
    [pscustomobject]@{ Binding = "$($_.Host):$($_.Port)"; Subject = $c.Subject; Expires = $c.NotAfter; DaysLeft = if ($c) { ($c.NotAfter - (Get-Date)).Days } else { "CERT MISSING" } }
}
netsh http show sslcert hostnameport=portal.example.com:443 | Select-String "Hostname|Hash"
Get-ChildItem Cert:\LocalMachine\My | Select-Object Subject, NotAfter, Thumbprint
```

- curl still gets `200`: HTTP.sys keeps using the copy it loaded. On the test server it kept working even after `iisreset`.
- The check prints `portal.example.com:443 … CERT MISSING`.
- `netsh` still shows a **Certificate Hash** for `portal.example.com:443`, but that hash is no longer in `Cert:\LocalMachine\My`.
- A time bomb: when Windows reloads the binding (for example after a reboot), https for portal is expected to stop working.

**Cause:** the binding points to a certificate that was deleted.

**Fix:** bind a valid certificate again (here: a new test certificate):

```powershell
$cert = New-SelfSignedCertificate -DnsName portal.example.com -CertStoreLocation Cert:\LocalMachine\My -NotAfter (Get-Date).AddYears(1)
(Get-WebBinding -Name Portal -Protocol https).RemoveSslCertificate()
(Get-WebBinding -Name Portal -Protocol https).AddSslCertificate($cert.Thumbprint, "My")
```

**Verify**

```powershell
netsh http show sslcert hostnameport=portal.example.com:443 | Select-String "Hash"
$cert.Thumbprint
curl.exe -k -s -o NUL -w "%{http_code}\n" https://portal.example.com/
```

- The `Certificate Hash` now equals the new thumbprint (in lower case).
- `IIS:\SslBindings` remembers what it read earlier in the same window: run the 11.9 check in a **new** PowerShell window to see the new certificate there.
- (`curl.exe` without `-k` fails until you trust the new test certificate, as in 11.6.)

---

## Scenario 10 · "Admin is open to the whole network"

**Break:** nothing; a review finding.

**Ticket:** "Security review: the Admin site answers from any machine, with no login."

**Look here**

```powershell
Get-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/authentication/anonymousAuthentication -Name enabled
Get-WebConfiguration -PSPath IIS:\ -Location Admin -Filter system.webServer/security/ipSecurity | Select-Object allowUnlisted
Show-SiteLog Admin 10
```

- `anonymousAuthentication enabled = True`, `allowUnlisted = True` → anyone can open it.
- In the log, `c-ip` shows addresses from outside the admin network, and `cs-username` is always `-`.

**Fix:** topic 05.2 (Basic over https, or Windows authentication) and 05.4 (IP restrictions), then prove a refused client gets `401.2` / `403.503`.

---

## Summary: symptom → first log

| Symptom | Server header | First log | Key field |
|---|---|---|---|
| 503, whole site or part | Microsoft-HTTPAPI/2.0 | HTTPERR | `Disabled` / `AppOffline` / `QueueFull` + queue name |
| 404 for every page of a name | Microsoft-HTTPAPI/2.0 | HTTPERR | `NotFound` (no binding) |
| 500 on every page | Microsoft-IIS/10.0 | W3SVC + detailed page | `500 19` + error code |
| 500 on one page | Microsoft-IIS/10.0 | W3SVC + Application log | `500 0 0` + ASP.NET 1309 |
| 401 on one file | Microsoft-IIS/10.0 | W3SVC + `icacls` | `401 3 5` |
| 404 although file exists | Microsoft-IIS/10.0 | W3SVC | `404 3` / `404 7` / `404 8` |
| 413 on upload | Microsoft-IIS/10.0 | W3SVC | `413 1` |
| slow | Microsoft-IIS/10.0 | W3SVC + `appcmd list requests` | `time-taken` |
| site will not start | — | System log (W3SVC), `Get-NetTCPConnection` | `0x80070020` |
| https does not connect | — | System log (Schannel), `netsh http show sslcert` | event 36871 / 36874 / 36887 |
| certificate deleted / expiring | — | expiry check (11.9), `netsh http show sslcert` | `CERT MISSING` / DaysLeft |
