# 12 · Applications, virtual directories, ASP.NET and handlers

**Time:** 50 min · **Advanced**

**You will learn:**
- the three levels inside IIS: site → application → virtual directory
- add a virtual directory (= Apache `Alias`, Nginx `alias`)
- add an application with its **own** pool
- install ASP.NET and run real `.aspx` pages
- what a **handler mapping** is, and the errors when it is missing
- make a slow page and an error page: you need them in topics 13 and 14

**Before you start:** topics 01–06 done.

---

## 12.1 · Site, application, virtual directory

```
Site  Portal                      http://portal.example.com/
 ├── application  /                C:\inetpub\portal           PortalPool
 │     └── virtual directory /docs  C:\paybank-docs              (same pool, just another folder)
 └── application  /app             C:\inetpub\portal-app        PortalAppPool  (its own process)
```

- **Site** = bindings + at least one application (`/`).
- **Application** = a part of the site that can run in its **own pool**, with its own `web.config` root.
- **Virtual directory** = a URL path mapped to a folder somewhere else on disk. No own process.

## 12.2 · Virtual directory

```powershell
Import-Module WebAdministration
New-Item -ItemType Directory C:\paybank-docs -Force
Set-Content C:\paybank-docs\index.html "<h1>PayBank docs</h1>"
New-WebVirtualDirectory -Site Portal -Name docs -PhysicalPath C:\paybank-docs
curl.exe -s -H "Host: portal.example.com" http://localhost/docs/
& $env:windir\system32\inetsrv\appcmd.exe list vdirs
```

- `appcmd list vdirs` shows `Portal/docs/` → `C:\paybank-docs`.
- Permissions: the folder is outside `C:\inetpub`, so check it is readable by `IUSR` and `IIS_IUSRS`:

```powershell
icacls C:\paybank-docs
```

- A folder on `C:\` gives `Users` read by default, so it works. On a data disk with tight permissions you would get **401.3**.

## 12.3 · Application with its own pool

```powershell
New-Item -ItemType Directory C:\inetpub\portal-app -Force
Set-Content C:\inetpub\portal-app\index.html "<h1>PayBank app</h1>"
New-WebAppPool -Name PortalAppPool
New-WebApplication -Site Portal -Name app -PhysicalPath C:\inetpub\portal-app -ApplicationPool PortalAppPool
curl.exe -s -H "Host: portal.example.com" http://localhost/app/
& $env:windir\system32\inetsrv\appcmd.exe list apps
```

- `list apps` shows `Portal/` (PortalPool) and `Portal/app` (PortalAppPool).
- Stopping `PortalAppPool` breaks only `/app/`; the rest of Portal keeps working. Try it:

```powershell
Stop-WebAppPool PortalAppPool
curl.exe -s -o NUL -w "%{http_code}\n" -H "Host: portal.example.com" http://localhost/app/
curl.exe -s -o NUL -w "%{http_code}\n" -H "Host: portal.example.com" http://localhost/
Start-Sleep -Seconds 5
Start-WebAppPool PortalAppPool
Get-WebAppPoolState PortalAppPool
```

- Expected: `503` for `/app/`, `200` for `/`, and at the end `Started`.
- The pause matters: starting a pool that is still `Stopping` fails with `0x80070425`, and `/app/` then stays at 503.

## 12.4 · An .aspx page before ASP.NET is installed

```powershell
Set-Content C:\inetpub\portal-app\hello.aspx '<%@ Page Language="C#" %><h1>Hello from ASP.NET</h1><p>Time: <%= DateTime.Now %></p><p>Process: <%= System.Diagnostics.Process.GetCurrentProcess().Id %></p><p>Runs as: <%= System.Security.Principal.WindowsIdentity.GetCurrent().Name %></p>'
curl.exe -s -o NUL -w "%{http_code}\n" -H "Host: portal.example.com" http://localhost/app/hello.aspx
```

- Expected: **404**, logged as `404 3 50` (**404.3**): IIS has no handler and no MIME type for `.aspx`, so it refuses to send the source code. Good: the code is never leaked.

## 12.5 · Install ASP.NET

```powershell
Install-WindowsFeature Web-Asp-Net45
```

(Windows 10/11: `Enable-WindowsOptionalFeature -Online -All -FeatureName IIS-ASPNET45`)

```powershell
curl.exe -s -H "Host: portal.example.com" http://localhost/app/hello.aspx
```

- The page now runs. `Runs as:` shows `IIS APPPOOL\PortalAppPool`: the pool identity from topic 03.
- `Process:` is the PID of that pool's `w3wp.exe`. Compare:

```powershell
& $env:windir\system32\inetsrv\appcmd.exe list wp
```

## 12.6 · Handler mappings: who handles which file

```powershell
Get-WebHandler -PSPath "IIS:\Sites\Portal\app" | Where-Object Path -in "*.aspx", "*" | Select-Object Name, Path, Verb, Modules
```

- A **handler** is the code that makes the response for a request. IIS picks it by the file extension (`Path`).
- `PageHandlerFactory-Integrated…` handles `*.aspx`; `StaticFile` handles everything else (`*`).
- Apache equivalent: `AddHandler` / `SetHandler`; Nginx: `location ~ \.php$ { fastcgi_pass … }`.

| Error | Means | Usual cause |
|---|---|---|
| 404.3 | no handler and no MIME type for the extension | feature not installed (12.4) |
| 404.17 | dynamic content mapped to the static file handler | handler missing, file treated as static |
| 500.21 | handler points to a module that does not exist | ASP.NET removed or not registered |
| 500.19 | handler section invalid | typo in `<handlers>` in web.config |
| 502.5 / 500.30 | ASP.NET **Core** app failed to start | app crash at start-up (needs the ASP.NET Core Hosting Bundle, an **extra download**) |

## 12.7 · A slow page and an error page (used again later)

```powershell
Set-Content C:\inetpub\portal-app\slow.aspx '<%@ Page Language="C#" %><% System.Threading.Thread.Sleep(8000); %><h1>done after 8 seconds</h1>'
Set-Content C:\inetpub\portal-app\error.aspx '<%@ Page Language="C#" %><% throw new System.InvalidOperationException("Database connection pool exhausted"); %>'
curl.exe -s -o NUL -w "%{http_code} %{time_total}s\n" -H "Host: portal.example.com" http://localhost/app/slow.aspx
curl.exe -s -o NUL -w "%{http_code}\n" -H "Host: portal.example.com" http://localhost/app/error.aspx
```

- `slow.aspx`: `200` after about 8 s; `time-taken` in the log ≈ `8000`.
- `error.aspx`: `500`, logged as `500 0 0`.

**Read the error:**

```powershell
Start-Process http://portal.example.com/app/error.aspx
Get-WinEvent -LogName Application -MaxEvents 10 | Where-Object ProviderName -like "ASP.NET*" | Format-List TimeCreated, Id, Message
```

- In a browser **on the server** you see the yellow ASP.NET error page with the exception and the line.
- The Application event log has an **ASP.NET** warning, event **1309** (inside: "Event code: 3005 … An unhandled exception has occurred"), with the exception type, the message, the URL and the pool account.
- Visitors from other machines see only a short error page (`customErrors` default `RemoteOnly`).

---

## Exercises

1. Map `/manuals/` on Portal to `C:\paybank-manuals` without creating a new process.
2. Why give `/app` its own pool?
3. A colleague says "IIS shows our C# code to visitors". Is that possible for `.aspx` files? What do you see instead when ASP.NET is missing?
4. Which log tells you **what** exception `error.aspx` threw, and which event ID?
5. Which identity does `hello.aspx` run as, and where did that name come from?

## Answers

1. `New-WebVirtualDirectory -Site Portal -Name manuals -PhysicalPath C:\paybank-manuals` (create the folder first).
2. A crash, recycle, or memory problem in `/app` does not stop the rest of Portal; it can also have its own identity and .NET settings.
3. No: without ASP.NET, IIS answers 404.3 and never sends the file.
4. Application event log, source ASP.NET, event 1309 (the W3SVC log only shows `500 0 0`).
5. `IIS APPPOOL\PortalAppPool`: the virtual account IIS makes for each pool (ApplicationPoolIdentity).
