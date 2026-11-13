# 03 · Application pools: IIS's worker processes

**Time:** 45 min

**You will learn:** what a pool is, one pool per site, the pool identity and file permissions (`icacls`), recycling, idle timeout, starting and stopping pools, what visitors get when a pool is down (503), Rapid-Fail Protection, and the HTTPERR log.

---

## 03.1 · Pool = the worker processes behind a site

```
Site Portal ──► PortalPool ──► w3wp.exe  (identity: IIS AppPool\PortalPool)
Site Admin  ──► AdminPool  ──► w3wp.exe  (identity: IIS AppPool\AdminPool)
```

| Why one pool per site | |
|---|---|
| a crash in Admin does not stop Portal | isolation |
| each pool has its own identity | Portal's code cannot read Admin's files |
| recycle one site without touching others | maintenance |

Apache/Nginx equivalent: the www-data workers, except that IIS gives **each site** its own processes and user.

```powershell
Import-Module WebAdministration
Get-ChildItem IIS:\AppPools | Select-Object Name, State, ManagedRuntimeVersion
Get-Website | Select-Object Name, ApplicationPool
& $env:windir\system32\inetsrv\appcmd.exe list wp
```

## 03.2 · See a pool's worker process

```powershell
curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/
curl.exe -s -o NUL http://localhost:8090/
Get-CimInstance Win32_Process -Filter "Name='w3wp.exe'" | Select-Object ProcessId, @{n='Pool';e={($_.CommandLine -split '-ap "')[1].Split('"')[0]}}
```

One `w3wp.exe` per pool that has had traffic. In IIS Manager: server → **Worker Processes** shows the same, and double-clicking one shows the **requests running right now**.

## 03.3 · Identity: who reads the files?

| Identity | Means |
|---|---|
| **ApplicationPoolIdentity** (default) | a virtual account `IIS AppPool\<PoolName>`, made for that pool only |
| `IUSR` | the anonymous-user account for static files (topic 05) |
| `NetworkService`, `LocalSystem` | older, shared, more powerful: avoid `LocalSystem` |
| a domain service account | when the app must reach file shares or databases with Windows login |

```powershell
Get-ItemProperty IIS:\AppPools\PortalPool -Name processModel.identityType
icacls C:\inetpub\portal
```

`icacls` shows the folder's permissions (Windows' version of `ls -l` + chmod). By default `IIS_IUSRS` (all pool identities) and `IUSR` can **read** under `C:\inetpub`.

| icacls letters | Means |
|---|---|
| `(R)` read · `(RX)` read and run · `(M)` modify · `(F)` full | rights |
| `(OI)(CI)` | inherited by files and subfolders |

## 03.4 · Give one pool write access (uploads folder)

```powershell
New-Item -ItemType Directory C:\inetpub\portal\uploads
icacls C:\inetpub\portal\uploads /grant "IIS AppPool\PortalPool:(OI)(CI)M"
icacls C:\inetpub\portal\uploads
```

Only PortalPool may write there. Same rule as Linux: web files read-only; write only to data folders that need it (Apache: `chown -R` on `uploads`).

## 03.5 · Recycling: a planned restart

```powershell
(Get-ItemProperty IIS:\AppPools\PortalPool -Name recycling.periodicRestart.time).Value
Get-Process w3wp | Select-Object Id, StartTime
Restart-WebAppPool PortalPool
curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/
Get-Process w3wp | Select-Object Id, StartTime
```

| Setting | Default | Means |
|---|---|---|
| Regular time interval | **1740 min** (29 h) | recycle automatically |
| Specific times | none | e.g. 03:00 daily, chosen by many companies |
| Private memory limit | 0 (off) | recycle when the pool uses more memory |
| Overlapped recycle | on | start the new w3wp **before** stopping the old: no downtime |

- The value prints as `1.05:00:00` = 1 day 5 hours = 29 h = 1740 min.
- Right after the recycle you may briefly see **both** PIDs: the old worker finishes its last requests while the new one starts.

Recycling clears memory leaks; the first request after it may be slower (the app starts again). After the recycle, the PID is new.

## 03.6 · Idle timeout

```powershell
(Get-ItemProperty IIS:\AppPools\PortalPool -Name processModel.idleTimeout).Value
Set-ItemProperty IIS:\AppPools\PortalPool -Name processModel.idleTimeout -Value "00:05:00"
```

No request for 20 minutes (default) → w3wp stops. Users then complain "the first request in the morning is slow". For busy apps set it to `00:00:00` (never) or use **Start Mode: AlwaysRunning**:

```powershell
Set-ItemProperty IIS:\AppPools\PortalPool -Name startMode -Value AlwaysRunning
```

## 03.7 · Stop a pool: visitors get 503

```powershell
Stop-WebAppPool PortalPool
Get-WebAppPoolState PortalPool
curl.exe -i -H "Host: portal.example.com" http://localhost/
```

- `Get-WebAppPoolState` may say `Stopping` for a second, then `Stopped`.

Sample response:

```text
HTTP/1.1 503 Service Unavailable
Server: Microsoft-HTTPAPI/2.0
<h2>Service Unavailable</h2>
<hr><p>HTTP Error 503. The service is unavailable.</p>
```

- `Microsoft-HTTPAPI/2.0` → HTTP.sys answered: the request never reached a worker.
- **Not** in the site's W3SVC log → IIS never saw it.
- In the **HTTPERR** log, reason `Disabled` → "an administrator stopped this pool". The place to look.

```powershell
netsh http flush logbuffer
Get-Content C:\Windows\System32\LogFiles\HTTPERR\httperr*.log -Tail 3
```

Sample line:

```text
2026-11-13 01:16:51 ::1%0 49949 ::1%0 80 HTTP/1.1 GET / - - 503 2 Disabled PortalPool TCP
```

- `::1%0` → the client was this server itself (`localhost` over IPv6).
- `503 2` → status 503 for site ID 2 (Portal).
- `Disabled PortalPool` → the reason, and the pool.

Start it again. Wait a few seconds after stopping first: starting a pool that is still `Stopping` fails with `The service cannot accept control messages at this time. (0x80070425)`.

```powershell
Start-WebAppPool PortalPool
Get-WebAppPoolState PortalPool
curl.exe -I -H "Host: portal.example.com" http://localhost/
```

## 03.8 · Rapid-Fail Protection: why a pool stops by itself

```
crash ✕ 10:01   crash ✕ 10:02   crash ✕ 10:02   crash ✕ 10:04   crash ✕ 10:05  ──►  pool STOPPED → every visitor 503
```

| Setting | Default |
|---|---|
| Rapid-Fail Protection | enabled |
| Maximum failures | **5** |
| Failure interval | **5 minutes** |

```powershell
Get-ItemProperty IIS:\AppPools\PortalPool -Name failure | Select-Object rapidFailProtection, rapidFailProtectionMaxCrashes, rapidFailProtectionInterval
```

**Simulate it** by killing the worker 5 times (each kill counts as a crash):

```powershell
1..5 | ForEach-Object {
    curl.exe -s -o NUL -H "Host: portal.example.com" http://localhost/
    Start-Sleep -Seconds 2
    Get-Process w3wp | Where-Object { (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -match "PortalPool" } | Stop-Process -Force
}
Get-WebAppPoolState PortalPool
curl.exe -i -H "Host: portal.example.com" http://localhost/
```

- If the pool still says `Started`, run the loop once more: the 5 crashes must fall inside 5 minutes.
- The 503 now comes with HTTPERR reason **`AppOffline`** (the pool was taken offline because of errors), not `Disabled` (stopped by an admin): the log tells you which one happened.

**Find out why:**

```powershell
Get-WinEvent -LogName System -MaxEvents 20 | Where-Object ProviderName -eq "Microsoft-Windows-WAS" | Format-Table TimeCreated, Id, Message -Wrap
```

| WAS event ID | Means |
|---|---|
| 5009 | a worker process terminated unexpectedly (exit code shown) |
| 5011 | a worker process had a fatal communication error with WAS (it vanished) |
| 5002 | the pool was **disabled**: too many failures (Rapid-Fail) |

- Killing w3wp gives a mix of 5009 and 5011; a real application crash usually gives 5011 or 5009 too, plus an error in the **Application** log.

Sample line:

```text
11/13/2026 1:17:34 AM 5002 Application pool 'PortalPool' is being automatically disabled due to a series of failures in the process(es) serving that application pool.
```

**Fix:** find and fix the cause of the crashes (developers, Application event log), then start the pool. Starting it without a fix repeats the cycle.

```powershell
Start-WebAppPool PortalPool
```

---

## Exercises

1. Which pool runs the Admin site, and under which identity?
2. Recycle only AdminPool and prove its worker PID changed.
3. PortalPool is stopped. Where does the 503 appear: the W3SVC log, HTTPERR, or both?
4. Give AdminPool modify rights on `C:\inetpub\admin\reports` only.
5. A pool stopped itself at 03:12. Which log and event ID tell you why?

## Answers

1. `(Get-Website Admin).ApplicationPool` → AdminPool; identity `IIS AppPool\AdminPool` (ApplicationPoolIdentity).
2. Note `Get-Process w3wp`, `Restart-WebAppPool AdminPool`, `curl.exe http://localhost:8090/`, compare.
3. Only HTTPERR, reason `Disabled` (stopped by an admin; a Rapid-Fail stop shows `AppOffline`); the request never reached IIS.
4. `icacls C:\inetpub\admin\reports /grant "IIS AppPool\AdminPool:(OI)(CI)M"`.
5. System event log, source WAS: 5009/5011 for each crash, then 5002 for the pool being disabled.
