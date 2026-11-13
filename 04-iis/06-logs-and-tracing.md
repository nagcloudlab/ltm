# 06 · Logs and tracing

**Time:** 45 min

**You will learn:** the W3C log format and every default field, sub-status and win32-status, UTC times, log buffering, reading logs with PowerShell, logging settings, the HTTPERR log, Event Viewer, and Failed Request Tracing.

---

## 06.1 · Where the logs are

```powershell
Get-Website | Select-Object Name, ID
Get-ChildItem C:\inetpub\logs\LogFiles -Recurse | Select-Object FullName, Length, LastWriteTime
```

| Log | Where | Records |
|---|---|---|
| site log (W3C) | `C:\inetpub\logs\LogFiles\W3SVC<ID>\u_exYYMMDD.log` | every request that reached IIS |
| **HTTPERR** | `C:\Windows\System32\LogFiles\HTTPERR\httperr*.log` | requests HTTP.sys rejected (bad hostname, pool down, timeouts) |
| Event Viewer | System and Application logs | pool crashes, service start/stop |
| Failed Request Tracing | `C:\inetpub\logs\FailedReqLogFiles\` | step-by-step trace of chosen requests |

## 06.2 · Logs are buffered: flush them

IIS writes log lines in batches (about every minute). Your newest requests may not be in the file yet. File names use the **UTC** date, so the command builds the name from UTC:

```powershell
curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/nothing.html
netsh http flush logbuffer
Get-Content "C:\inetpub\logs\LogFiles\W3SVC$((Get-Website Portal).ID)\u_ex$((Get-Date).ToUniversalTime().ToString('yyMMdd')).log" -Tail 3
```

> "I just made a request and it's not in the log" → `netsh http flush logbuffer`.

## 06.3 · The default W3C line, field by field

Sample line (with the header line IIS writes above it):

```text
#Fields: date time s-ip cs-method cs-uri-stem cs-uri-query s-port cs-username c-ip cs(User-Agent) cs(Referer) sc-status sc-substatus sc-win32-status sc-bytes cs-bytes time-taken
2026-11-13 01:30:34 ::1 GET /nothing.html - 80 - ::1 curl/8.21.0 - 404 0 2 5091 94 3
```

| # | Field | Example | Means |
|---|---|---|---|
| 1 | `date` | 2026-11-13 | **UTC** date |
| 2 | `time` | 01:30:34 | **UTC** time (IST = +5:30 → 07:00:34) |
| 3 | `s-ip` | ::1 | server address (`::1` = localhost over IPv6) |
| 4 | `cs-method` | GET | method |
| 5 | `cs-uri-stem` | /nothing.html | path |
| 6 | `cs-uri-query` | - | query string (`-` = none) |
| 7 | `s-port` | 80 | port |
| 8 | `cs-username` | - | user if authenticated |
| 9 | `c-ip` | ::1 | client |
| 10 | `cs(User-Agent)` | curl/8.21.0 | spaces become `+` |
| 11 | `cs(Referer)` | - | |
| **12** | **`sc-status`** | **404** | status |
| **13** | **`sc-substatus`** | **0** | **why** (404.**0**) |
| 14 | `sc-win32-status` | 2 | Windows error code (2 = file not found, 5 = access denied, 64 = client disconnected) |
| 15 | `sc-bytes` | 5091 | bytes sent to the client |
| 16 | `cs-bytes` | 94 | bytes received from the client |
| 17 | `time-taken` | 3 | **milliseconds** |

- These 17 fields are the default on Windows Server 2022 (IIS 10). Older servers often log 15: no `sc-bytes cs-bytes`.

`cs-` = client to server, `sc-` = server to client, `s-` = server, `c-` = client. The `#Fields:` line names the columns: **read it first**, columns can be changed (06.6).

## 06.4 · Read and filter with PowerShell

```powershell
$log = Get-Item "C:\inetpub\logs\LogFiles\W3SVC$((Get-Website Portal).ID)\u_ex$((Get-Date).ToUniversalTime().ToString('yyMMdd')).log"
Get-Content $log.FullName -Tail 10
Get-Content $log.FullName -Wait -Tail 0
```

(`-Wait` = `tail -f`; stop with `Ctrl+C`.)

```powershell
Select-String -Path $log.FullName -Pattern " 404 "
Get-Content $log.FullName | Where-Object { $_ -notlike "#*" } | ForEach-Object { ($_ -split " ")[11] + "." + ($_ -split " ")[12] } | Group-Object | Sort-Object Count -Descending | Select-Object Count, Name
Get-Content $log.FullName | Where-Object { $_ -notlike "#*" } | Sort-Object { [int]($_ -split " ")[16] } | Select-Object -Last 3
```

| Linux | PowerShell |
|---|---|
| `tail -n 10` / `tail -f` | `Get-Content -Tail 10` / `-Wait` |
| `grep` | `Select-String` |
| `grep -v '^#'` | `Where-Object { $_ -notlike "#*" }` |
| `cut -d' ' -f12` | `($_ -split " ")[11]` (counts from 0) |
| `sort -k17,17n` | `Sort-Object { [int]($_ -split " ")[16] }` (time-taken) |
| `sort \| uniq -c \| sort -rn` | `Group-Object \| Sort-Object Count -Descending` |

## 06.5 · Generate the codes from topic 05 and read them

- New PowerShell window? Run the `$log = …` line from 06.4 again first.

```powershell
curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/web.config
curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/index.html.bak
curl.exe -s -o NUL -H "Host: portal.example.com" "http://localhost/$(('a' * 250 + '/') * 20)"
curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/files/
curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/data.yaml
netsh http flush logbuffer
Get-Content $log.FullName -Tail 5 | ForEach-Object { $f = $_ -split " "; "{0} {1}.{2} win32={3}" -f $f[4], $f[11], $f[12], $f[13] }
```

Expected, in order:
- `404.8` → hidden segment (`web.config`).
- `404.7` → blocked extension (`.bak`).
- `404.14` → URL longer than `maxUrl`.
- `403.14` → folder without default document (or `200` if you left browsing on).
- `200` for `.yaml` (you added the MIME type in 04.6; `404.3` without it).

## 06.6 · Logging settings

```powershell
Get-ItemProperty "IIS:\Sites\Portal" -Name logFile | Select-Object directory, logFormat, period, localTimeRollover, logExtFileFlags
```

| Setting | Default | Note |
|---|---|---|
| format | W3C | keep it |
| directory | `%SystemDrive%\inetpub\logs\LogFiles` | move to a data disk on busy servers |
| rollover | Daily | new file per day: `u_exYYMMDD.log` |
| local time rollover | off | only changes **file names**; times inside stay **UTC** |
| fields | 17 defaults (06.3) | **cs-host** (the site name) is **off** |

Add `cs-host` (keep all the default fields):

```powershell
Set-ItemProperty "IIS:\Sites\Portal" -Name logFile.logExtFileFlags -Value "Date,Time,ClientIP,UserName,ServerIP,Method,UriStem,UriQuery,HttpStatus,Win32Status,TimeTaken,ServerPort,UserAgent,Referer,HttpSubStatus,Host,BytesSent,BytesRecv"
curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/
netsh http flush logbuffer
Get-Content $log.FullName -Tail 3
```

- A new `#Fields:` line appears with the new columns. A field that was never logged **cannot be recovered** later.
- IIS keeps its **own column order**, whatever order you type: `cs-host` lands just before `sc-status`, and `sc-bytes cs-bytes` just before `time-taken`.
- So the column numbers move: in this file `sc-status` is now index `[12]` and `time-taken` `[17]`. Always read the newest `#Fields:` line before counting columns.

Sample line:

```text
#Fields: date time s-ip cs-method cs-uri-stem cs-uri-query s-port cs-username c-ip cs(User-Agent) cs(Referer) cs-host sc-status sc-substatus sc-win32-status sc-bytes cs-bytes time-taken
2026-11-13 01:30:35 ::1 GET / - 80 - ::1 curl/8.21.0 - portal.example.com 200 0 0 330 82 574
```

Put the default fields back, so the column numbers in the next topics stay the same (topic 10 adds `cs-host` again):

```powershell
Set-ItemProperty "IIS:\Sites\Portal" -Name logFile.logExtFileFlags -Value "Date,Time,ClientIP,UserName,ServerIP,Method,UriStem,UriQuery,HttpStatus,Win32Status,BytesSent,BytesRecv,TimeTaken,ServerPort,UserAgent,Referer,HttpSubStatus"
```

## 06.7 · HTTPERR: what IIS never saw

```powershell
Stop-WebAppPool PortalPool
Start-Sleep -Seconds 5
curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/
Start-WebAppPool PortalPool
Get-WebAppPoolState PortalPool
netsh http flush logbuffer
Get-ChildItem C:\Windows\System32\LogFiles\HTTPERR | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content -Tail 5
```

- If the line is not there yet, wait a minute and read again: HTTPERR is also written in batches.
- `Start-Sleep` gives the pool time to stop: starting a pool that is still `Stopping` fails with `0x80070425`. The last command must say `Started`.

Sample line:

```text
#Fields: date time c-ip c-port s-ip s-port cs-version cs-method cs-uri streamid streamid_ex sc-status s-siteid s-reason s-queuename transport
2026-11-13 01:30:35 ::1%0 50232 ::1%0 80 HTTP/1.1 GET / - - 503 2 Disabled PortalPool TCP
```

- `503 2` → status 503 for site ID 2.
- `Disabled PortalPool` → the reason and the pool. The reason is field 14 (`[13]` in PowerShell).

| `s-reason` | Means |
|---|---|
| `Disabled` | an admin stopped the site's pool → 503 |
| `AppOffline` | the pool was taken offline after errors (Rapid-Fail, topic 03.8) → 503 |
| `NotFound` | the Host name matches no binding → 404 (02.9) |
| `QueueFull` | too many requests waiting for the pool → 503 (topic 08) |
| `Timer_ConnectionIdle` | idle connection closed: normal |
| `Connection_Dropped` | client disconnected |

> A 503 that is **missing** from the site log is in HTTPERR.

## 06.8 · Event Viewer

```powershell
Get-WinEvent -LogName System -MaxEvents 50 | Where-Object { $_.ProviderName -in "Microsoft-Windows-WAS","Microsoft-Windows-IIS-W3SVC" } | Format-Table TimeCreated, Id, LevelDisplayName, Message -Wrap
Get-WinEvent -LogName Application -MaxEvents 20 | Where-Object LevelDisplayName -eq "Error" | Format-Table TimeCreated, ProviderName, Message -Wrap
eventvwr.msc
```

| Log | Look for |
|---|---|
| System, source **WAS** | pool crashes (5009, 5011), pool disabled (5002), identity problems |
| System, source **W3SVC** | site could not start (port in use) |
| Application, **ASP.NET** / **.NET Runtime** | application exceptions |

Event Viewer is the Windows `journalctl`.

## 06.9 · Failed Request Tracing (FREB): replay one bad request

```powershell
Install-WindowsFeature Web-Http-Tracing
```

(Windows 10/11: `Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpTracing`)

Turn tracing on for Portal and add a rule "trace every request that ends with 400–599":

```powershell
Import-Module WebAdministration
Set-WebConfigurationProperty -PSPath IIS:\ -Filter "system.applicationHost/sites/site[@name='Portal']/traceFailedRequestsLogging" -Name enabled -Value $true
Add-WebConfigurationProperty -PSPath IIS:\ -Location Portal -Filter system.webServer/tracing/traceFailedRequests -Name "." -Value @{path="*"}
Add-WebConfigurationProperty -PSPath IIS:\ -Location Portal -Filter "system.webServer/tracing/traceFailedRequests/add[@path='*']/traceAreas" -Name "." -Value @{provider="WWW Server"; areas="Authentication,Security,Filter,StaticFile,CGI,Compression,Cache,RequestNotifications,Module"; verbosity="Verbose"}
Set-WebConfigurationProperty -PSPath IIS:\ -Location Portal -Filter "system.webServer/tracing/traceFailedRequests/add[@path='*']/failureDefinitions" -Name statusCodes -Value "400-599"
```

- Same in IIS Manager: site **Portal** → Actions → **Failed Request Tracing…** → Enable; then **Failed Request Tracing Rules** → Add… → All content → Status code(s) `400-599` → Finish.
- Type the `areas` list exactly: one unknown area name makes **every** request of the site fail with `500.0`, error code `0x80070057`.

Reproduce, then read the newest trace:

```powershell
curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/nothing.html
Start-Sleep -Seconds 2
Get-ChildItem C:\inetpub\logs\FailedReqLogFiles -Recurse | Select-Object FullName, Length
$x = Get-ChildItem C:\inetpub\logs\FailedReqLogFiles -Recurse -Filter fr*.xml | Sort-Object LastWriteTime | Select-Object -Last 1
[xml]$trace = Get-Content $x.FullName
$trace.failedRequest | Format-List url, statusCode, timeTaken
($trace.failedRequest.Event | Where-Object { $_.RenderingInfo.Opcode -eq "MODULE_SET_RESPONSE_ERROR_STATUS" }).EventData.Data | ForEach-Object { "$($_.Name) = $($_.'#text')" }
```

- One `frNNNNNN.xml` file per failed request, plus `freb.xsl` (the style sheet) in `C:\inetpub\logs\FailedReqLogFiles\W3SVC2\`.
- The last command prints the step that set the error: `ModuleName = IIS Web Core`, `HttpStatus = 404`, `HttpSubStatus = 0`, `ErrorCode = 2147942402` (= `0x80070002`, file not found).
- Opened in a browser, the same file shows a report: **Request Summary** and **Compact View** (every step with timings). Some browsers show raw XML for local files; the PowerShell lines above always work.

```powershell
Start-Process $x.FullName
```

| Rule ideas | Catches |
|---|---|
| status `500-599` | server errors with the failing module |
| time taken > 5 s | slow requests: which step was slow |
| status `401.3` | permission problems |

> Turn tracing off when done: it slows the server and fills the disk.

```powershell
Set-WebConfigurationProperty -PSPath IIS:\ -Filter "system.applicationHost/sites/site[@name='Portal']/traceFailedRequestsLogging" -Name enabled -Value $false
```

---

## Exercises

1. Your request is not in today's log. What command makes it appear?
2. A log line ends `413 1 0 5177 180 31` and the method is `POST`. Which reason is it, and what was sent?
3. Find the 3 slowest requests in today's Portal log with PowerShell.
4. Users report 503 but Portal's log has no 503 lines. Where do you look, and for which reason?
5. Add `cs-host` to Portal's logs and explain why it matters when several sites share one log folder.

## Answers

1. `netsh http flush logbuffer`.
2. `413.1`: request body larger than `maxAllowedContentLength`; IIS refused it after reading only the headers (`cs-bytes` 180), in 31 ms. Older IIS logs this as `404.13`.
3. 06.4, the `Sort-Object { [int]($_ -split " ")[16] }` line (`time-taken`, ms). After 06.6 added `cs-host`, use `[17]`.
4. HTTPERR log, reason `Disabled` (pool stopped by an admin), `AppOffline` (pool stopped by Rapid-Fail) or `QueueFull`.
5. `Host` flag in `logExtFileFlags`; without it you cannot tell which host name a request used.
