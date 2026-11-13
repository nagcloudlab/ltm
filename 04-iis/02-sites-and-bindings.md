# 02 · Sites and bindings

**Time:** 40 min

**You will learn:** create a site in IIS Manager and in PowerShell, the four parts of a binding, several sites on one port by host name, a site on its own port, the Windows hosts file, site IDs and log folders, and what HTTP.sys answers for an unknown name.

---

## 02.1 · Site = folder + pool + bindings

```
Site "Portal"
 ├── physical path  C:\inetpub\portal          (= DocumentRoot)
 ├── application pool  PortalPool               (topic 03)
 └── bindings  http  *:80:portal.example.com    (= Listen + ServerName)
```

## 02.2 · Create the Portal site (PowerShell)

```powershell
Import-Module WebAdministration
New-Item -ItemType Directory C:\inetpub\portal
Set-Content C:\inetpub\portal\index.html "<h1>PayBank Portal</h1><p>served by IIS</p>"
New-WebAppPool -Name PortalPool
New-Website -Name Portal -PhysicalPath C:\inetpub\portal -ApplicationPool PortalPool -Port 80 -HostHeader portal.example.com
Get-Website
```

Same in IIS Manager: Sites → right-click → **Add Website…** → name, physical path, pool, binding.

## 02.3 · A binding has four parts

```
http  :  *              :  80   :  portal.example.com
type     IP address        port    host name
         (* = All Unassigned)
```

| Part | Means | Apache / Nginx |
|---|---|---|
| type | `http` (`https` on Day 2) | |
| IP | `*` = any address; or one specific IP | `0.0.0.0` vs one address |
| port | the door | `Listen` / `listen` |
| host name | the website name; empty = any name | `ServerName` / `server_name` |

```powershell
Get-WebBinding -Name Portal
& $env:windir\system32\inetsrv\appcmd.exe list sites
```

## 02.4 · Test with the Host header

```powershell
curl.exe -H "Host: portal.example.com" http://localhost/
curl.exe -H "Host: something-else" http://localhost/
curl.exe http://localhost/
```

| Host sent | Answered by |
|---|---|
| `portal.example.com` | Portal (exact host-name binding) |
| anything else | Default Web Site (its binding `*:80:` has **no** host name = catch-all) |

## 02.5 · The Windows hosts file

```powershell
Copy-Item C:\Windows\System32\drivers\etc\hosts C:\Windows\System32\drivers\etc\hosts.bak
Add-Content C:\Windows\System32\drivers\etc\hosts "`r`n127.0.0.1 portal.example.com admin.example.com"
ipconfig /flushdns
curl.exe http://portal.example.com/
Start-Process http://portal.example.com/
```

- Same idea as `/etc/hosts`.
- The `` `r`n `` starts a new line first, in case the file does not end with one.
- `ipconfig /flushdns` clears Windows' name cache so the change is seen at once.

## 02.6 · More names for one site (= ServerAlias)

```powershell
New-WebBinding -Name Portal -Protocol http -Port 80 -HostHeader www.portal.example.com
Get-WebBinding -Name Portal
curl.exe -H "Host: www.portal.example.com" http://localhost/
```

Each extra name is one more binding.

## 02.7 · A site on its own port

```powershell
New-Item -ItemType Directory C:\inetpub\admin
Set-Content C:\inetpub\admin\index.html "<h1>PayBank Admin on 8090</h1>"
New-WebAppPool -Name AdminPool
New-Website -Name Admin -PhysicalPath C:\inetpub\admin -ApplicationPool AdminPool -Port 8090
curl.exe http://localhost:8090/
New-NetFirewallRule -DisplayName "IIS Admin 8090" -Direction Inbound -Protocol TCP -LocalPort 8090 -Action Allow | Select-Object DisplayName, Enabled
```

From another machine: `http://[win-ip]:8090/`. The **Windows Defender Firewall** rule is needed (the installer already opened 80, rule "World Wide Web Services (HTTP Traffic-In)").

```powershell
Get-NetFirewallRule -DisplayName "World Wide Web Services (HTTP Traffic-In)" | Select-Object DisplayName, Enabled
```

## 02.8 · Site IDs and log folders

```powershell
Get-Website | Select-Object Name, ID
Get-ChildItem C:\inetpub\logs\LogFiles
```

| Site | ID | Log folder |
|---|---|---|
| Default Web Site | 1 | `W3SVC1` |
| Portal | 2 | `W3SVC2` |
| Admin | 3 | `W3SVC3` |

Logs are found by **ID**, not by name. A log folder appears after the site's first request (and after the log buffer is written, topic 06).

## 02.9 · Break it: a name no site knows → 404 from HTTP.sys

- The Default Web Site's binding `*:80:` has no host name, so it catches every unknown name.
- Give it a host name (`localhost`) for a moment: now port 80 only knows `localhost`, `portal.example.com` and `www.portal.example.com`.

```powershell
& $env:windir\system32\inetsrv\appcmd.exe set site /site.name:"Default Web Site" /bindings:http/*:80:localhost
Start-Sleep -Seconds 2
curl.exe -i -H "Host: unknown.example.com" http://localhost/
curl.exe -i http://127.0.0.1/
netsh http flush logbuffer
Get-Content C:\Windows\System32\LogFiles\HTTPERR\httperr*.log -Tail 2
& $env:windir\system32\inetsrv\appcmd.exe set site /site.name:"Default Web Site" /bindings:http/*:80:
```

Sample response:

```text
HTTP/1.1 404 Not Found
Server: Microsoft-HTTPAPI/2.0
<h2>Not Found</h2>
<hr><p>HTTP Error 404. The requested resource is not found.</p>
```

Sample line (HTTPERR):

```text
2026-11-13 01:15:19 127.0.0.1 49905 127.0.0.1 80 HTTP/1.1 GET / - - 404 - NotFound - TCP
```

- `Microsoft-HTTPAPI/2.0` → HTTP.sys answered; IIS never saw the request, so the site log has **no** line.
- `404 - NotFound` in HTTPERR → the Host name matched **no binding** on that port (`-` = no site).
- Compare a real missing file: `Server: Microsoft-IIS/10.0`, a line in the site log, sub-status `404.0`.
- Older Windows versions answer the same mistake with `400 Bad Request - Invalid Hostname`; you still meet that text in old tickets.
- Common real cause: users browse by IP, or by a name that was never added as a binding.
- Fix: add the binding (02.6), or keep a catch-all site.

## 02.10 · Break it: two sites, the same binding

```powershell
New-Website -Name PortalCopy -PhysicalPath C:\inetpub\portal -Port 80 -HostHeader portal.example.com
Get-Website PortalCopy | Select-Object Name, State
Start-Website PortalCopy
Remove-Website PortalCopy
```

`New-Website` warns or the site stays **Stopped**; `Start-Website` fails with `Cannot create a file when that file already exists. (0x800700B7)`: the binding is already taken by Portal. IIS refuses identical bindings (Nginx only warns: `conflicting server name … ignored`).

---

## Exercises

1. Add the binding `portal` (no domain) to Portal and prove it works.
2. Which site answers `http://localhost:8090/`, and why does it not need a host name?
3. Which folder holds the Admin site's logs?
4. A user gets a plain `Not Found` page with `Server: Microsoft-HTTPAPI/2.0`, and the site log has nothing. Which component answered, and what do you check?
5. Give the Admin site a second port, 8091, without removing 8090.

## Answers

1. `New-WebBinding -Name Portal -Port 80 -HostHeader portal`, then `curl.exe -H "Host: portal" http://localhost/`.
2. Admin: it is the only site on port 8090, so an empty host name is enough.
3. `C:\inetpub\logs\LogFiles\W3SVC<Admin's ID>\` (3 if created in this order): `(Get-Website Admin).ID`.
4. HTTP.sys: no binding matched the Host name (HTTPERR reason `NotFound`). Check the bindings for that host name and port.
5. `New-WebBinding -Name Admin -Port 8091`, plus a firewall rule for 8091.
