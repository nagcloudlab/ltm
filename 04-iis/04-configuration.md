# 04 · Configuration: applicationHost.config, web.config, features

**Time:** 45 min

**You will learn:** where IIS Manager writes its settings, server vs site config, `web.config`, editing with PowerShell and `appcmd`, default documents, directory browsing, custom error pages, MIME types, backing up and restoring config, and the 500.19 error.

---

## 04.1 · Where IIS Manager writes

```
C:\Windows\System32\inetsrv\config\applicationHost.config   ← server-wide + every site and pool
        └── C:\inetpub\portal\web.config                     ← one site (overrides server values)
                └── C:\inetpub\portal\docs\web.config         ← one folder (overrides the site)
```

| | Apache | IIS |
|---|---|---|
| server file | `apache2.conf` | `applicationHost.config` |
| per-folder file | `.htaccess` | `web.config` |
| format | directives | **XML** |
| inner overrides outer | yes | yes |

```powershell
Import-Module WebAdministration
notepad C:\Windows\System32\inetsrv\config\applicationHost.config
Select-String -Path C:\Windows\System32\inetsrv\config\applicationHost.config -Pattern '<site name=' -Context 0,4
```

Read only. Edit through IIS Manager, PowerShell or `appcmd`: one XML mistake here breaks **every** site.

> **Notepad** on a 64-bit Windows opens the real file. Some 32-bit editors see a different (redirected) folder and show an old copy: use Notepad or VS Code.

## 04.2 · Back up before you change (the IIS .bak)

```powershell
& $env:windir\system32\inetsrv\appcmd.exe add backup "before-lab-$(Get-Date -Format yyyyMMdd-HHmm)"
& $env:windir\system32\inetsrv\appcmd.exe list backup
Get-ChildItem C:\Windows\System32\inetsrv\backup
Get-ChildItem C:\inetpub\history
```

| Backup | Made by |
|---|---|
| `inetsrv\backup\<name>` | you, with `appcmd add backup` |
| `C:\inetpub\history\CFGHISTORY_000000000x` | IIS automatically, every 2 min after a change (keeps 10) |

- `appcmd list backup` shows your backup **and** the automatic `CFGHISTORY_…` copies: both can be restored by name.

Restore your newest backup (all sites and pools go back to that moment):

```powershell
$last = (Get-ChildItem C:\Windows\System32\inetsrv\backup | Sort-Object LastWriteTime | Select-Object -Last 1).Name
& $env:windir\system32\inetsrv\appcmd.exe restore backup $last
```

- Right now this changes nothing: nothing was changed since the backup.
- To restore an older one, copy its name from `appcmd list backup`: `appcmd restore backup "<name>"`.

## 04.3 · Default Document (= DirectoryIndex)

```powershell
Get-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/defaultDocument/files/add -Name value | Select-Object Value
Add-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/defaultDocument/files -Name "." -Value @{value="home.html"} -AtIndex 0
Get-Content C:\inetpub\portal\web.config
```

The default list: `Default.htm`, `Default.asp`, `index.htm`, `index.html`, `iisstart.htm`, `default.aspx`; the first file found wins. The change was written to the site's **web.config** (created if missing).

```xml
<configuration>
  <system.webServer>
    <defaultDocument>
      <files>
        <add value="home.html" />
      </files>
    </defaultDocument>
  </system.webServer>
</configuration>
```

## 04.4 · Directory Browsing: 403.14

```powershell
New-Item -ItemType Directory C:\inetpub\portal\files
New-Item C:\inetpub\portal\files\report.pdf, C:\inetpub\portal\files\db.sql -ItemType File
curl.exe -I -H "Host: portal.example.com" http://localhost/files/
```

**403** (sub-status **403.14**: no default document, browsing disabled: the safe default, like Nginx's autoindex off).

Turn a listing on for that folder only, then off again:

```powershell
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal\files" -Filter system.webServer/directoryBrowse -Name enabled -Value $true
curl.exe -s -H "Host: portal.example.com" http://localhost/files/
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal\files" -Filter system.webServer/directoryBrowse -Name enabled -Value $false
```

## 04.5 · Custom error pages, and detailed errors for admins

```powershell
Set-Content C:\inetpub\portal\404.html "<h1>Sorry, no such page</h1>"
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter "system.webServer/httpErrors/error[@statusCode='404']" -Name prefixLanguageFilePath -Value ""
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter "system.webServer/httpErrors/error[@statusCode='404']" -Name path -Value "404.html"
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter "system.webServer/httpErrors/error[@statusCode='404']" -Name responseMode -Value File
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/httpErrors -Name errorMode -Value Custom
curl.exe -i -H "Host: portal.example.com" http://localhost/nothing.html
Set-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/httpErrors -Name errorMode -Value DetailedLocalOnly
curl.exe -i -H "Host: portal.example.com" http://localhost/nothing.html
```

- With `Custom`, curl gets your page "Sorry, no such page", and the status stays `404 Not Found`.
- `responseMode File` sends the file as the error body; `prefixLanguageFilePath ""` means "the path is relative to the site folder".
- Avoid `ExecuteURL` for a plain `.html` error page: IIS then answers **`200 OK`** with the sorry page, so monitoring tools and search engines think the missing page exists.
- Back on `DetailedLocalOnly` (the default), curl **on the server** gets the long detailed IIS page instead: curl on the server counts as a local visitor.
- Visitors from other machines always get your custom page.

| `errorMode` | Visitors see | Default |
|---|---|---|
| `DetailedLocalOnly` | detailed page **only** on the server itself, short page elsewhere | **yes** |
| `Custom` | always the short/custom page | |
| `Detailed` | everyone sees details (path, module, error code) | never in production |

**Troubleshooting trick:** reproduce the problem **in a browser on the server**. The detailed page shows the sub-status, the physical path, the module, the handler and the Windows error code.

## 04.6 · MIME types: 404.3

```powershell
Set-Content C:\inetpub\portal\data.yaml "status: ok"
curl.exe -I -H "Host: portal.example.com" http://localhost/data.yaml
```

- Expected: `HTTP/1.1 404 Not Found`, and the log line shows `404 3 50` (sub-status 3, Windows error 50 = "not supported").
- If this already answers 200, your IIS version knows `.yaml`: try another made-up extension, e.g. `data.paybank`.

**404.3**: the file exists, but IIS has no Content-Type for `.yaml`, so it refuses to send it (Apache would send `text/plain` or a default). Add the type:

```powershell
Add-WebConfigurationProperty -PSPath "IIS:\Sites\Portal" -Filter system.webServer/staticContent -Name "." -Value @{fileExtension=".yaml"; mimeType="text/yaml"}
curl.exe -i -H "Host: portal.example.com" http://localhost/data.yaml
```

## 04.7 · Break it: a typo in web.config → 500.19

```powershell
Copy-Item C:\inetpub\portal\web.config C:\inetpub\portal\web.config.bak
(Get-Content C:\inetpub\portal\web.config) -replace "</system.webServer>", "</system.webserver>" | Set-Content C:\inetpub\portal\web.config
curl.exe -i -H "Host: portal.example.com" http://localhost/
Start-Process http://portal.example.com/
```

- The typo: the closing tag `</system.webserver>` no longer matches `<system.webServer>`. XML names are **case-sensitive**.
- Text added **after** `</configuration>` is ignored by IIS; a mistake **inside** the file is what breaks the site.

| What you see | Means |
|---|---|
| **500.19** Internal Server Error | configuration data is invalid |
| error code `0x8007000d` + "Configuration file is not well-formed XML" | malformed XML |
| detailed page (on the server) | names the **config file** and the **line** |
| **every** page of the site fails | one web.config breaks the whole site |

```powershell
Copy-Item C:\inetpub\portal\web.config.bak C:\inetpub\portal\web.config -Force
curl.exe -I -H "Host: portal.example.com" http://localhost/
```

| 500.19 code | Usual cause |
|---|---|
| `0x8007000d` | malformed XML, or a section for a **module not installed** (e.g. URL Rewrite) |
| `0x80070021` | a section is **locked** at server level (e.g. authentication) |
| `0x80070005` | the pool identity cannot **read** web.config (permissions) |

First question for a 500.19: **"who changed web.config?"**

## 04.8 · Edit config from the command line

| Task | PowerShell | appcmd |
|---|---|---|
| read a setting | `Get-WebConfigurationProperty -PSPath … -Filter … -Name …` | `appcmd list config "Portal" -section:directoryBrowse` |
| set a setting | `Set-WebConfigurationProperty …` | `appcmd set config "Portal" -section:directoryBrowse /enabled:false` |
| server-wide | `-PSPath IIS:\` | `appcmd set config -section:…` |

```powershell
& $env:windir\system32\inetsrv\appcmd.exe list config "Portal" -section:directoryBrowse
```

---

## Exercises

1. Make `start.html` the first default document for Admin only. Which file was changed?
2. Show a listing for `C:\inetpub\admin\files` and nowhere else.
3. A `.json` file returns 404.3 on an old server. Explain and fix.
4. Restore all IIS config to your backup from 04.2.
5. Portal shows 500.19 with code `0x8007000d` right after a release. What do you do first?

## Answers

1. `Add-WebConfigurationProperty -PSPath "IIS:\Sites\Admin" -Filter system.webServer/defaultDocument/files -Name "." -Value @{value="start.html"} -AtIndex 0`; `C:\inetpub\admin\web.config`.
2. `Set-WebConfigurationProperty -PSPath "IIS:\Sites\Admin\files" -Filter system.webServer/directoryBrowse -Name enabled -Value $true`.
3. No MIME type registered for `.json`: add `fileExtension=".json" mimeType="application/json"` in staticContent.
4. `appcmd restore backup "<name>"` (list names with `appcmd list backup`).
5. Open the page on the server to see file and line, then compare `web.config` with the previous version from the release or a backup.
