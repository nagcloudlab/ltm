# 08 · Performance: compression, caching, queues, counters, load test

**Time:** 40 min

**You will learn:** static and dynamic compression, browser caching with `clientCache`, output caching, the request queue (`queueLength`) and its 503, connection limits and timeouts, live counters with `Get-Counter`, and a small load test that shows the numbers moving.

---

## 08.1 · Make a page worth compressing

```powershell
Import-Module WebAdministration
$text = (1..3000 | ForEach-Object { "PayBank statement line $_ amount 1000.00" }) -join "`n"
Set-Content C:\inetpub\portal\statement.html "<html><body><pre>$text</pre></body></html>"
(Get-Item C:\inetpub\portal\statement.html).Length
curl.exe -s -o NUL -w "%{size_download} bytes\n" -H "Host: portal.example.com" http://localhost/statement.html
```

## 08.2 · Static compression

Static compression is installed with the web server. Check it, and whether gzip is answering:

```powershell
Get-WindowsFeature Web-Stat-Compression, Web-Dyn-Compression
curl.exe -s -o NUL -D - -H "Accept-Encoding: gzip" -H "Host: portal.example.com" http://localhost/statement.html
```

The **first** request is usually **not** compressed. IIS only compresses a file that is asked for often:

| Setting (`system.webServer/serverRuntime`) | Default | Means |
|---|---|---|
| `frequentHitThreshold` | **2** | hits needed… |
| `frequentHitTimePeriod` | **10 s** | …within this time before IIS compresses and caches it |

Send it a few times quickly:

```powershell
1..3 | ForEach-Object { curl.exe -s -o NUL -D - -H "Accept-Encoding: gzip" -H "Host: portal.example.com" http://localhost/statement.html | Select-String "Content-Encoding|Content-Length" }
curl.exe -s -o NUL -w "%{size_download} bytes\n" -H "Accept-Encoding: gzip" -H "Host: portal.example.com" http://localhost/statement.html
```

`Content-Encoding: gzip` appears and the size drops by about 90%.

For a lab, compress from the first hit:

```powershell
Set-WebConfigurationProperty -PSPath IIS:\ -Filter system.webServer/serverRuntime -Name frequentHitThreshold -Value 1
```

Compressed copies are kept in `C:\inetpub\temp\IIS Temporary Compressed Files\<PoolName>\`.

## 08.3 · Dynamic compression

```powershell
Install-WindowsFeature Web-Dyn-Compression
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/urlCompression -Name doDynamicCompression -Value $true
Get-WebConfiguration -PSPath "IIS:\Sites\Portal" -Filter system.webServer/urlCompression | Select-Object doStaticCompression, doDynamicCompression
```

(Windows 10/11: `Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpCompressionDynamic`)

| | Static | Dynamic |
|---|---|---|
| for | `.html`, `.css`, `.js` files | pages made by the app (ASP.NET, JSON APIs) |
| cost | compressed **once**, cached on disk | compressed **every** request: CPU |
| default | on | off |
| IIS turns it off by itself | | when CPU is above 90% (`dynamicCompressionDisableCpuUsage`) |

Same idea as Apache `mod_deflate` and Nginx `gzip on`.

## 08.4 · Browser caching: clientCache

```powershell
New-Item -ItemType Directory C:\inetpub\portal\static -Force
Set-Content C:\inetpub\portal\static\site.css "body { font-family: sans-serif; }"
curl.exe -sI -H "Host: portal.example.com" http://localhost/static/site.css | Select-String "Cache-Control|ETag|Last-Modified"
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal\static" -Filter system.webServer/staticContent/clientCache -Name cacheControlMode -Value UseMaxAge
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal\static" -Filter system.webServer/staticContent/clientCache -Name cacheControlMaxAge -Value "7.00:00:00"
curl.exe -sI -H "Host: portal.example.com" http://localhost/static/site.css | Select-String "Cache-Control"
```

`Cache-Control: max-age=604800` (7 days). The browser re-uses the file without asking.

| `cacheControlMode` | Header |
|---|---|
| `NoControl` (default) | none: the browser decides |
| `UseMaxAge` | `Cache-Control: max-age=N` |
| `UseExpires` | `Expires: <date>` |
| `DisableCache` | `Cache-Control: no-cache` |

**Conditional request: 304.** The browser sends back the date it got in `Last-Modified`:

```powershell
$lm = ((curl.exe -sI -H "Host: portal.example.com" http://localhost/static/site.css | Select-String "Last-Modified").ToString() -replace "Last-Modified: ","").Trim()
curl.exe -sI -H "Host: portal.example.com" -H "If-Modified-Since: $lm" http://localhost/static/site.css
```

- Browsers also send `If-None-Match` with the `ETag`; the date is used here because PowerShell 5.1 mangles the quotes inside an ETag when passing it to `curl.exe`.

**304 Not Modified**, no body. In the log: `304 0 0` with a time-taken of 0 or 1 ms.

## 08.5 · Kernel cache and output cache

| Cache | Where | Gives |
|---|---|---|
| **HTTP.sys kernel cache** | inside the kernel | repeat requests for static files answered without waking w3wp |
| **IIS output cache** | in w3wp | cached copies of dynamic pages for N seconds |

```powershell
1..3 | ForEach-Object { curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/index.html }
netsh http show cachestate
```

- Lists the URLs HTTP.sys has cached right now, e.g. `URL: http://portal.example.com:80/index.html`, `Request queue name: PortalPool`.
- A file is cached only after the same `frequentHitThreshold` rule (asked for often enough), so ask for it a few times first.
- No requests for a while → `There were no cache entries`: the cache empties itself.

## 08.6 · The request queue: 503 when it is full

```
HTTP.sys ──► [ queue for PortalPool : 1000 places ] ──► w3wp threads busy
                       full? → 503 Service Unavailable, HTTPERR reason QueueFull
```

```powershell
(Get-ItemProperty IIS:\AppPools\PortalPool -Name queueLength).Value
```

| Setting | Default | Note |
|---|---|---|
| `queueLength` | **1000** | requests waiting for a free thread |
| when full | 503 from `Microsoft-HTTPAPI/2.0` | **not** in the site log, only in HTTPERR as `QueueFull` |

Raising it to 5000 only hides the problem longer: the real question is **why** requests are not finishing (a slow database, a lock). Look at `time-taken` (topic 07).

**See it on purpose**: shrink the queue to 10 places, then send 3000 requests, 200 at a time (on a lab VM only):

```powershell
Set-ItemProperty IIS:\AppPools\PortalPool -Name queueLength -Value 10
Start-Sleep -Seconds 2
curl.exe -s --parallel --parallel-max 200 --out-null -w "%{http_code}\n" -H "Host: portal.example.com" "http://localhost/statement.html?n=[1-3000]" | Group-Object | Select-Object Count, Name
netsh http flush logbuffer
(Select-String -Path C:\Windows\System32\LogFiles\HTTPERR\httperr*.log -Pattern "QueueFull").Count
Select-String -Path C:\Windows\System32\LogFiles\HTTPERR\httperr*.log -Pattern "QueueFull" | Select-Object -Last 1 | ForEach-Object Line
Set-ItemProperty IIS:\AppPools\PortalPool -Name queueLength -Value 1000
```

- `--parallel --parallel-max 200` → curl keeps 200 requests open at once; `[1-3000]` → 3000 different URLs.
- `--out-null` throws the bodies away; `-w "%{http_code}\n"` prints only each status code.
- Expected: most `200`, but hundreds of **`503`** (on the test server: 2045 × 200, 955 × 503).
- Each 503 has an HTTPERR line with reason `QueueFull`; the site log has none of them.
- The last command puts the normal size back.

Sample line:

```text
2026-11-13 02:02:52 ::1%0 51036 ::1%0 80 HTTP/1.1 GET /statement.html?n=3000 - - 503 2 QueueFull PortalPool TCP
```

- With the normal 1000 places, the same test gives only `200`. In real life the queue fills when the **back end is slow** (requests do not finish), not because of a test.

## 08.7 · Limits and timeouts

```powershell
Get-ItemProperty "IIS:\Sites\Portal" -Name limits | Select-Object connectionTimeout, maxConnections, maxBandwidth
```

| Setting | Default | Apache / Nginx |
|---|---|---|
| `limits.connectionTimeout` | 120 s | `Timeout` / `client_body_timeout` |
| `limits.maxConnections` | 4294967295 (no limit) | `MaxRequestWorkers` / `worker_connections` |
| `limits.maxBandwidth` | no limit | |
| keep-alive (`httpProtocol allowKeepAlive`) | on | `KeepAlive On` / `keepalive_timeout` |
| pool `processModel.maxProcesses` | 1 | more than 1 = "web garden": rarely a good idea |

## 08.8 · Live counters and a load test

Open a **second** PowerShell window and watch the counters:

```powershell
Get-Counter -Counter "\Web Service(_Total)\Current Connections", "\Web Service(_Total)\Get Requests/sec", "\HTTP Service Request Queues(PortalPool)\CurrentQueueSize", "\HTTP Service Request Queues(PortalPool)\RejectedRequests" -SampleInterval 2 -Continuous
```

In the first window, send 2000 requests, 50 at a time, without and with gzip:

```powershell
Measure-Command { curl.exe -s --parallel --parallel-max 50 --out-null -H "Host: portal.example.com" "http://localhost/statement.html?n=[1-2000]" } | Select-Object TotalSeconds
Measure-Command { curl.exe -s --parallel --parallel-max 50 --out-null -H "Accept-Encoding: gzip" -H "Host: portal.example.com" "http://localhost/statement.html?n=[1-2000]" } | Select-Object TotalSeconds
```

- `Measure-Command` prints how long the whole run took (on a 2-CPU test server: under 1 s each).
- The counters in the second window jump while it runs.

The same test from your **Ubuntu** VM with the Apache `ab` tool (add `portal.example.com` with the Windows VM's address to `/etc/hosts` first, and allow port 80 in any cloud firewall):

```bash
sudo apt install -y apache2-utils
ab -n 2000 -c 50 http://portal.example.com/statement.html
ab -n 2000 -c 50 -H "Accept-Encoding: gzip" http://portal.example.com/statement.html
```

| Counter | Look for |
|---|---|
| `Current Connections` | rises with load, falls after |
| `Get Requests/sec` | the throughput |
| `CurrentQueueSize` | should stay near **0**; growing = workers too slow |
| `RejectedRequests` | above 0 = 503 QueueFull happened |

- `ab`: compare the lines `Requests per second` and `Total transferred` with and without gzip.
- The `-Continuous` counter window runs until you press `Ctrl+C`.

Also: Task Manager → Details → `w3wp.exe` (CPU, memory); `perfmon` for graphs.

---

## Exercises

1. `statement.html` is not compressed on the first request but is on the third. Why?
2. Make every file under `/static/` cacheable for 30 days and prove it with curl.
3. Users see 503, the site log has none, HTTPERR says `QueueFull`. What is full, what is its default size, and what do you investigate?
4. Which counter tells you requests are waiting in PortalPool's queue?
5. Why is dynamic compression off by default?

## Answers

1. `frequentHitThreshold` = 2 hits within 10 s: IIS compresses only files asked for often.
2. `cacheControlMode=UseMaxAge`, `cacheControlMaxAge="30.00:00:00"` on `IIS:\Sites\Portal\static`; `curl.exe -sI … | Select-String Cache-Control` shows `max-age=2592000`.
3. The application pool's request queue (`queueLength`, 1000). Find why requests are slow: `time-taken`, the app, the database, worker process requests in IIS Manager.
4. `\HTTP Service Request Queues(PortalPool)\CurrentQueueSize`.
5. It costs CPU on every request; static files are compressed once and cached.
