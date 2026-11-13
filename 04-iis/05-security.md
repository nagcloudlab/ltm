# 05 · Security: authentication, IP rules, request filtering, headers

**Time:** 45 min

**You will learn:** anonymous vs Basic vs Windows authentication (401), NTFS-permission errors (401.3), IP and domain restrictions (403.503), Request Filtering and its 404.x codes, removing version headers, adding security headers, and HTTP redirects.

---

## 05.1 · Authentication types

| Type | Who gets in | Login box | Use |
|---|---|---|---|
| **Anonymous** (default) | everyone, as user `IUSR` | no | public sites |
| **Basic** | Windows user name + password | browser box | simple, **https only** |
| **Windows** | the logged-in Windows/domain user | none inside the company network | intranet apps |

Install Basic and Windows authentication:

```powershell
Install-WindowsFeature Web-Basic-Auth, Web-Windows-Auth
```

(Windows 10/11: `Enable-WindowsOptionalFeature -Online -FeatureName IIS-BasicAuthentication, IIS-WindowsAuthentication`)

## 05.2 · Protect the Admin site with Basic authentication

Create a local Windows user for the test:

```powershell
$p = Read-Host -AsSecureString "Password for webadmin"
New-LocalUser -Name webadmin -Password $p -PasswordNeverExpires
```

Turn anonymous **off** and Basic **on** for the Admin site:

```powershell
Import-Module WebAdministration
Set-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/authentication/anonymousAuthentication -Name enabled -Value $false
Set-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/authentication/basicAuthentication -Name enabled -Value $true
curl.exe -I http://localhost:8090/
curl.exe -I -u webadmin:yourpassword http://localhost:8090/
curl.exe -I -u webadmin:wrong http://localhost:8090/
```

| Result | Sub-status | Means |
|---|---|---|
| 401 + `WWW-Authenticate: Basic realm="localhost"` | **401.2** | no credentials sent: log in |
| 200 | | right user and password |
| 401 | **401.1** | wrong user name or password |

Authentication sections are **locked** at server level, so they live in `applicationHost.config` (`-Location Admin`), not in the site's web.config: putting them in web.config gives **500.19** with `0x80070021`.

## 05.3 · NTFS permissions: 401.3

Anonymous requests read files as **IUSR**. Remove its access to one file:

```powershell
Set-Content C:\inetpub\portal\secret.html "<h1>secret</h1>"
icacls C:\inetpub\portal\secret.html /inheritance:r /grant "Administrators:F"
curl.exe -I -H "Host: portal.example.com" http://localhost/secret.html
icacls C:\inetpub\portal\secret.html /reset
```

**401.3**: "Unauthorized: access is denied due to an ACL". It looks like a login problem but is a **file permission** problem (the Linux 403 / errno 13 equivalent). `icacls /reset` brings back inherited permissions.

## 05.4 · IP and domain restrictions: 403.503

```powershell
Install-WindowsFeature Web-IP-Security
```

(Windows 10/11: `Enable-WindowsOptionalFeature -Online -FeatureName IIS-IPSecurity`)

Allow only the server itself and the office network into Admin:

```powershell
Set-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/ipSecurity -Name allowUnlisted -Value $false
Add-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/ipSecurity -Name "." -Value @{ipAddress="127.0.0.1"; allowed="true"}
Add-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/ipSecurity -Name "." -Value @{ipAddress="::1"; allowed="true"}
Add-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/ipSecurity -Name "." -Value @{ipAddress="10.0.0.0"; subnetMask="255.255.255.0"; allowed="true"}
curl.exe -I -u webadmin:yourpassword http://localhost:8090/
```

- `::1` is `127.0.0.1` in IPv6. `curl.exe http://localhost` connects over IPv6, so without `::1` the server itself is refused.

See a refusal without a second machine: call the server by its own network address, which is **not** on the list.

```powershell
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1).IPAddress
curl.exe -I -u webadmin:yourpassword "http://${ip}:8090/"
```

- Answer: **403 Forbidden** (unless your server's address happens to be in 10.0.0.0/24).
- In the Admin log the line ends with `403 503 5`: sub-status **503** = "IP address rejected" (older IIS: 403.6).

Sample line:

```text
2026-11-13 01:26:19 10.160.0.2 GET / - 8090 - 10.160.0.2 curl/8.21.0 - 403 503 5 4925 134 138
```

- From a neighbour's machine or your laptop you get the same 403.

| Setting | Means | Nginx / Apache |
|---|---|---|
| `allowUnlisted=false` | deny everyone not listed | `deny all;` / `Require` only listed |
| `add ipAddress … allowed=true` | allow this address or network | `allow` / `Require ip` |
| `denyAction` | `Forbidden` (403), `NotFound` (404), `AbortRequest` (drop) | |

## 05.5 · Request Filtering: the bouncer before the site

Request Filtering is on by default. It rejects requests **before** they reach a handler, mostly with **404 + a revealing sub-status** (attackers see only 404; the admin sees why in the log). Too-big uploads get **413**.

| Rule | Default | Rejected as |
|---|---|---|
| body size `maxAllowedContentLength` | 30,000,000 bytes (~28.6 MB) | **413.1** (older IIS: 404.13) |
| URL length `maxUrl` | 4096 | **404.14** |
| number of URL parts (folders) `maxUrlSegments` | 32 | **404.20** |
| query string `maxQueryString` | 2048 | **404.15** |
| file extension denied (`.config`, `.mdb`, …) | on | **404.7** |
| hidden segment (`bin`, `App_Data`, `web.config`) | on | **404.8** |
| verb denied | none by default | **404.6** |
| double-escaped URL | denied | **404.11** |

**Try them:**

```powershell
curl.exe -I -H "Host: portal.example.com" http://localhost/web.config
curl.exe -I -H "Host: portal.example.com" "http://localhost/$(('a' * 250 + '/') * 20)"
fsutil file createnew $env:TEMP\big.bin 40000000
curl.exe -s -o NUL -w "%{http_code}\n" -H "Host: portal.example.com" -X POST --data-binary "@$env:TEMP\big.bin" http://localhost/
```

- `web.config` → **404** (hidden segment, 404.8).
- The long URL (20 folders of 250 letters = 5020 characters) → **404** (over `maxUrl`, 404.14).
- 40 MB upload → **413** `Request Entity Too Large` (over 30 MB, 413.1).
- The long URL is built from folders on purpose:
  - HTTP.sys itself refuses any **single** part longer than 260 characters with `400 Bad Request`, before IIS can see it.
  - More than 32 folders hits a different limit first (`maxUrlSegments`, 404.20).
- Topic 06 shows the sub-statuses in the log.

Deny a file type and a verb for Portal:

```powershell
Add-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/security/requestFiltering/fileExtensions -Name "." -Value @{fileExtension=".bak"; allowed="false"}
Add-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/security/requestFiltering/verbs -Name "." -Value @{verb="TRACE"; allowed="false"}
Set-Content C:\inetpub\portal\index.html.bak "old"
curl.exe -I -H "Host: portal.example.com" http://localhost/index.html.bak
curl.exe -I -X TRACE -H "Host: portal.example.com" http://localhost/
```

Raise the upload limit to 100 MB for one site:

```powershell
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/security/requestFiltering/requestLimits -Name maxAllowedContentLength -Value 104857600
```

> If an ASP.NET app is involved, it has its **own** limit too (`maxRequestLength` in `system.web`, in KB). Both must allow the size.

## 05.6 · Hide the version headers

```powershell
curl.exe -sI -H "Host: portal.example.com" http://localhost/ | Select-String "Server|X-Powered-By"
Set-WebConfigurationProperty -PSPath IIS:\ -Filter system.webServer/security/requestFiltering -Name removeServerHeader -Value $true
Remove-WebConfigurationProperty -PSPath IIS:\ -Filter system.webServer/httpProtocol/customHeaders -Name "." -AtElement @{name="X-Powered-By"}
curl.exe -sI -H "Host: portal.example.com" http://localhost/ | Select-String "Server|X-Powered-By"
```

| Header | Leaks | Fix |
|---|---|---|
| `Server: Microsoft-IIS/10.0` | product and version | `removeServerHeader=true` (IIS 10, Windows Server 2016 1709+) |
| `X-Powered-By: ASP.NET` | framework | remove the custom header (it exists only once ASP.NET is installed; on a plain server the remove command just warns "not found") |

(Errors answered by HTTP.sys still say `Microsoft-HTTPAPI/2.0`; removing that needs a registry setting, `DisableServerHeader`.)

## 05.7 · Security headers

```powershell
Add-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/httpProtocol/customHeaders -Name "." -Value @{name="X-Content-Type-Options"; value="nosniff"}
Add-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/httpProtocol/customHeaders -Name "." -Value @{name="X-Frame-Options"; value="SAMEORIGIN"}
curl.exe -sI -H "Host: portal.example.com" http://localhost/ | Select-String "X-"
```

IIS Manager: site → **HTTP Response Headers**.

## 05.8 · HTTP Redirect

```powershell
Install-WindowsFeature Web-Http-Redirect
New-Item -ItemType Directory C:\inetpub\portal\old
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal\old" -Filter system.webServer/httpRedirect -Name enabled -Value $true
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal\old" -Filter system.webServer/httpRedirect -Name destination -Value "/"
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal\old" -Filter system.webServer/httpRedirect -Name httpResponseStatus -Value Permanent
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal\old" -Filter system.webServer/httpRedirect -Name exactDestination -Value $true
curl.exe -I -H "Host: portal.example.com" http://localhost/old/
```

- Expected: `301 Moved Permanently` with `Location: http://portal.example.com/`.
- Without `exactDestination`, IIS adds the rest of the path to the destination and you get `Location: http://portal.example.com//`.

| `httpResponseStatus` | Code |
|---|---|
| `Permanent` | 301 |
| `Found` | 302 |
| `Temporary` | 307 |
| `PermRedirect` | 308 |

Pattern-based redirects (like `mod_rewrite`) need the separate **URL Rewrite** module, downloaded from Microsoft; a web.config using `<rewrite>` without it gives 500.19.

## 05.9 · Put the lab server back (needed for the next topics)

- The next topics call Admin without a password. Undo 05.2 and 05.4 for Admin.
- The next topics also read the `Server:` header to tell IIS from HTTP.sys, so show it again for now. On a real production server you would keep it hidden.

```powershell
Set-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/authentication/basicAuthentication -Name enabled -Value $false
Set-WebConfigurationProperty -PSPath IIS:\ -Location Admin -Filter system.webServer/security/authentication/anonymousAuthentication -Name enabled -Value $true
Clear-WebConfiguration -PSPath IIS:\ -Location Admin -Filter system.webServer/security/ipSecurity
Set-WebConfigurationProperty -PSPath IIS:\ -Filter system.webServer/security/requestFiltering -Name removeServerHeader -Value $false
curl.exe -I http://localhost:8090/
```

- Expected: `200 OK` without `-u`, and `Server: Microsoft-IIS/10.0` is back. The `webadmin` user stays: the lab (topic 10) uses it again.

---

## Exercises

1. Make Portal's `/reports/` folder require Basic authentication while the rest stays anonymous.
2. A user gets 401.3 on a PDF. What is wrong and how do you check it?
3. Allow only `10.0.0.0/24` into Portal and send everyone else **404** instead of 403.
4. Uploads above 30 MB fail with 413. Which setting and which sub-status?
5. Remove `X-Powered-By` and the IIS version from Portal's responses and prove it.

## Answers

1. `-Location "Portal/reports"` with anonymous `false` and basic `true`.
2. NTFS permissions: IUSR (or the pool identity) cannot read the file; `icacls <file>`.
3. ipSecurity `allowUnlisted=false`, add `10.0.0.0/255.255.255.0 allowed=true`, `denyAction=NotFound`.
4. `maxAllowedContentLength` (Request Filtering); `413.1` in the log (`404.13` on older IIS).
5. 05.6 commands; `curl.exe -sI … | Select-String "Server|X-Powered-By"` shows nothing.
