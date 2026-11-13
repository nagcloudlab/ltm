# 11 · HTTPS: certificates, bindings, SNI, TLS errors

**Time:** 50 min · **Advanced**

**You will learn:**
- what a certificate is and where Windows keeps it (the certificate store)
- make a test certificate, add an `https` binding on port 443, use SNI
- trust the certificate so `curl.exe` stops complaining
- force HTTPS (Require SSL → 403.4)
- check expiry dates for every certificate IIS uses
- read TLS problems in the System event log (source **Schannel**)

**Before you start:** topics 01–06 done; `portal.example.com` points to `127.0.0.1` in the hosts file (02.5).

---

## 11.1 · The idea in one picture

```
Browser ──"hello, I want portal.example.com"──► HTTP.sys on 443
        ◄──── certificate for portal.example.com ── (picked from the Windows certificate store)
        checks: right name? not expired? signed by someone I trust?
        ──── encrypted HTTP request ────────────►  Portal site (same as before)
```

- The certificate proves the server's name. It has a **name**, an **expiry date**, and a **signer** (issuer).
- Windows keeps certificates in **stores**, not in files: `Cert:\LocalMachine\My` = "Personal" store of the computer.
- Apache/Nginx point to `.crt` and `.key` files; IIS points to a certificate **thumbprint** (its fingerprint) in the store.

## 11.2 · Look at the certificate store

```powershell
Import-Module WebAdministration
Get-ChildItem Cert:\LocalMachine\My | Select-Object Subject, NotAfter, Thumbprint
certlm.msc
```

- `certlm.msc` opens the same store in a window: **Personal → Certificates**.
- On a fresh lab VM the list may be empty.

## 11.3 · Make a test certificate

```powershell
$cert = New-SelfSignedCertificate -DnsName portal.example.com -CertStoreLocation Cert:\LocalMachine\My -NotAfter (Get-Date).AddYears(1)
$cert | Select-Object Subject, NotAfter, Thumbprint
```

- **Self-signed** = signed by itself. Good for a lab; browsers do not trust it.
- In a company, the certificate comes from the company's certificate authority or a public one, as a `.pfx` file you import.
- **Skip the next block in the lab**: it needs a real `.pfx` file (without one it fails with "The PFX file could not be found").

```powershell
Import-PfxCertificate -FilePath C:\certs\portal.pfx -CertStoreLocation Cert:\LocalMachine\My -Password (Read-Host -AsSecureString "pfx password")
```


## 11.4 · Add the https binding (with SNI)

```powershell
New-WebBinding -Name Portal -Protocol https -Port 443 -HostHeader portal.example.com -SslFlags 1
(Get-WebBinding -Name Portal -Protocol https).AddSslCertificate($cert.Thumbprint, "My")
Get-WebBinding -Name Portal
netsh http show sslcert
```

- `-SslFlags 1` = **SNI** (Server Name Indication): the browser says the host name **before** the encryption starts, so many HTTPS sites can share one IP and port 443, each with its own certificate.
- `netsh http show sslcert` shows the link HTTP.sys keeps: `Hostname:port : portal.example.com:443` → `Certificate Hash` = the thumbprint.
- IIS Manager: Portal → **Bindings…** → Add → Type `https`, Host name, tick "Require Server Name Indication", choose the certificate.

## 11.5 · Test it

```powershell
curl.exe -I https://portal.example.com/
curl.exe -k -I https://portal.example.com/
curl.exe -v -k -o NUL https://portal.example.com/
```

- First line fails: `curl: (60) schannel: SEC_E_UNTRUSTED_ROOT (0x80090325) - The certificate chain was issued by an authority that is not trusted.`
- `-k` = "do not check the certificate": the page loads, so the binding works.
- `-v` shows the connection steps: `Established connection to portal.example.com (127.0.0.1 port 443)`, `ALPN: server accepted http/1.1`, `schannel: …` lines. (curl on Windows uses Schannel and does not print the TLS version.)

## 11.6 · Trust the test certificate on this machine

```powershell
$root = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
$root.Open("ReadWrite")
$root.Add($cert)
$root.Close()
curl.exe -I https://portal.example.com/
```

- Now the certificate's signer (itself) is in **Trusted Root Certification Authorities**, so the check passes without `-k`.
- If curl complains about revocation (`CRYPT_E_NO_REVOCATION_CHECK`), add `--ssl-no-revoke`: a self-signed certificate has no revocation list.
- Do this only on lab machines.

## 11.7 · Open the firewall for 443

```powershell
Get-NetFirewallRule -DisplayName "World Wide Web Services (HTTPS Traffic-In)" | Select-Object DisplayName, Enabled
Enable-NetFirewallRule -DisplayName "World Wide Web Services (HTTPS Traffic-In)"
```

- IIS creates this rule when installed; make sure it is enabled.

## 11.8 · Force HTTPS: Require SSL → 403.4

```powershell
Set-WebConfigurationProperty -PSPath IIS:\ -Location Portal -Filter system.webServer/security/access -Name sslFlags -Value Ssl
Start-Sleep -Seconds 2
curl.exe -I -H "Host: portal.example.com" http://localhost/
curl.exe -I https://portal.example.com/
```

- Plain http now gets **403**; the log line ends `403 4 5` (`403.4` "SSL required"). https still gets 200.
- Give IIS a second or two after the change: a request sent at the same instant may still get the old answer.
- Redirecting http → https automatically needs the **URL Rewrite** module (**extra download** from Microsoft) or a load balancer in front.
- Turn it off again, because the next topics use plain http:

```powershell
Set-WebConfigurationProperty -PSPath IIS:\ -Location Portal -Filter system.webServer/security/access -Name sslFlags -Value None
```

## 11.9 · Expiry check for every certificate IIS uses

```powershell
Get-ChildItem IIS:\SslBindings | ForEach-Object {
    $c = Get-Item "Cert:\LocalMachine\My\$($_.Thumbprint)" -ErrorAction SilentlyContinue
    [pscustomobject]@{ Binding = "$($_.Host):$($_.Port)"; Subject = $c.Subject; Expires = $c.NotAfter; DaysLeft = if ($c) { ($c.NotAfter - (Get-Date)).Days } else { "CERT MISSING" } }
}
```

- An expired certificate is one of the most common "the site is down" calls.
- `CERT MISSING` = the binding points to a thumbprint that is no longer in the store (someone deleted or renewed it without re-binding).
- Renewal = import the new certificate, then re-bind (11.4) with the new thumbprint.

## 11.10 · Read TLS problems: Schannel events

- TLS errors never reach the W3SVC log: the request is not even decrypted.
- Windows writes them to the **System** event log, source **Schannel**.

```powershell
Get-WinEvent -FilterHashtable @{ LogName = "System"; ProviderName = "Schannel" } -MaxEvents 10 -ErrorAction SilentlyContinue | Format-Table TimeCreated, Id, Message -Wrap
```

| Event ID | Means |
|---|---|
| 36874 | client and server share **no** TLS version/cipher (old client, or old protocol switched off) |
| 36887 | the server **received** a fatal alert from the client (often "unknown CA" = client does not trust the cert) |
| 36888 | the server **sent** a fatal alert |
| 36871 | the server could not use its certificate's private key |
| 36882 | **this machine, as a client**, got a certificate it does not trust (e.g. `curl.exe` without `-k` on the server, 11.5) |

**Try an old protocol:**

```powershell
curl.exe -k -I --tlsv1.0 --tls-max 1.0 https://portal.example.com/
```

- On a fresh Windows Server 2022 this **works** (`200`): TLS 1.0 is still enabled by default. A finding for the security team: it should be switched off (registry settings under `SCHANNEL\Protocols`, then a reboot).
- After it is switched off, curl shows a handshake error instead, and a Schannel event may appear.

---

## Exercises

1. Which store and which thumbprint does Portal's https binding use? Show both with commands.
2. Add `www.portal.example.com` to the certificate story: what goes wrong if you add an https binding for that name with the same certificate?
3. Make plain http return 403.4 for Portal only, prove it, then undo it.
4. Write the expiry check so it prints only certificates with fewer than 30 days left.
5. A partner says "browser shows the site is not secure, curl says untrusted root". What is the cause and the fix in a company?

## Answers

1. `netsh http show sslcert` (Certificate Hash, Certificate Store Name `My`) or `Get-ChildItem IIS:\SslBindings`.
2. The certificate only names `portal.example.com`: the browser reports a name mismatch. Make a certificate with both names: `New-SelfSignedCertificate -DnsName portal.example.com, www.portal.example.com …`.
3. 11.8 commands with `-Value Ssl`, `curl.exe -I -H "Host: portal.example.com" http://localhost/`, then `-Value None`.
4. Add `| Where-Object { $_.DaysLeft -is [int] -and $_.DaysLeft -lt 30 }` after the loop.
5. The certificate is self-signed or signed by an authority the clients do not trust; use a certificate from the company or a public authority.
