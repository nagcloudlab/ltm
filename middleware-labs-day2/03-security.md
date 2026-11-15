# Lab 3 — Secure the payment API: tokens, gateway checks and TLS

- **Needs:** [Day 2 start](00-day2-start.md) done (Day 1 stack healthy; `python3-jwt`, `jq`, `openjdk-21-jdk-headless` installed); Kong on Day 1 stage 4
- **You build:** JWT access tokens from a small token issuer, a JWT-protected Kong route `/api/v2/payment`, and HTTPS on Nginx port 443 with your own certificate chain

```text
curl --(1) client_id + secret--> issuer 127.0.0.1:9000 --> access token (JWT, RS256)
curl --(2) Bearer token--------> Kong 127.0.0.1:8000/api/v2/payment --> Tomcat 127.0.0.1:8080
curl --(3) HTTPS---------------> Nginx :443 (portal.example.test) --> portal files, Tomcat
```

- Day 1 `/api/payment` with the API key keeps working; you add a second, token-protected path beside it.
- Private keys are generated on your laptop in `~/lab/security/` and never go into Git.
- Use one terminal (**Terminal A**) for all commands unless a step says **Terminal B**. Shell variables such as `$TOKEN` live only in the terminal where you set them.

## 1. Get ready

- Work from the security scripts folder and prove the Day 1 stack answers.

Go to the scripts folder:

```bash
cd ~/ltm/middleware-labs-day2/project-files/security
```

List the supplied files:

```bash
ls -l
```

Create your private working folder:

```bash
mkdir -p ~/lab/security
```

Check the services:

```bash
systemctl is-active apache2 nginx tomcat payment-kong
```

Check the gateway with the Day 1 API key:

```bash
curl -s -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

Check ports 443 and 9000 are free:

```bash
sudo ss -lntp '( sport = :443 or sport = :9000 )'
```

- **Expected:** four `active` lines, `Payment Service OK`, and only the header line from `ss` (nothing listening yet).
- `*.sh` files are executable; run them as `./name.sh` from this folder.

## 2. Authentication and authorization — what you already saw on Day 1

- **Authentication** = who are you? (password, API key, token). Failure: **401**.
- **Authorization** = what may you do? (groups, ACL, scopes). Failure: **403**.

Admin area without a password (Apache, Lab 1):

```bash
curl -I http://portal.example.test/admin/
```

- **Expected:** `HTTP/1.1 401 Unauthorized` with the header that asks for Basic credentials:

```text
WWW-Authenticate: Basic realm="Payment Operations"
```

Show the header curl sends (type your Lab 1 admin password when asked):

```bash
curl -sv -u admin -o /dev/null http://portal.example.test/admin/
```

- Find the line starting `> Authorization: Basic`. Sample line (password `s3cret`):

```text
> Authorization: Basic YWRtaW46czNjcmV0
```

Decode the sample value (replace it with yours to see your own password):

```bash
echo 'YWRtaW46czNjcmV0' | base64 -d
```

- **Expected:** `admin:s3cret` — user name and password in plain text.
- **Why:** Basic auth is **encoding, not encryption**. Anyone who sees the request sees the password; only HTTPS (step 12) hides it.

Kong without an API key:

```bash
curl -i http://127.0.0.1:8000/api/payment/status
```

Kong with a valid key that is not in the allowed group:

```bash
curl -i -H 'apikey: blocked-key-456' http://127.0.0.1:8000/api/payment/status
```

- **Expected:** `401` with `WWW-Authenticate: Key` and `"message":"No API key found in request"`, then `403` with `"message":"You cannot consume this service"`.

| Code | Meaning | Day 1 example |
| --- | --- | --- |
| 401 | Not authenticated: no or bad credential | Apache `/admin/` without password; Kong without key |
| 403 | Authenticated, but not allowed | Kong `blocked-partner` (ACL) |

## 3. Build a JWT by hand and read it

- A **JWT** (JSON Web Token) is three base64url parts joined by dots: `header.payload.signature`.
- `make-jwt.sh` builds one with bash and openssl. HS256 = HMAC-SHA256 with a shared secret.

Read the script:

```bash
cat make-jwt.sh
```

Make a token valid for 300 seconds:

```bash
./make-jwt.sh 300
```

Keep a fresh one in a variable:

```bash
TOKEN=$(./make-jwt.sh 300)
```

Show the three parts on separate lines:

```bash
echo "$TOKEN" | tr '.' '\n'
```

Try plain base64 on the payload:

```bash
echo "$TOKEN" | cut -d. -f2 | base64 -d
```

- **Expected:** the JSON may print, followed by `base64: invalid input`.
- **Why:** JWT uses **base64url** (`-` and `_` instead of `+` and `/`) and drops the `=` padding, so plain `base64` complains.

Read the script that decodes properly:

```bash
cat jwt-decode.sh
```

Decode header and payload:

```bash
./jwt-decode.sh "$TOKEN"
```

- Sample output:

```text
{
  "alg": "HS256",
  "typ": "JWT"
}
{
  "iss": "https://auth.example.com",
  "sub": "mobile-app",
  "aud": "payment-api",
  "iat": 1794730092,
  "nbf": 1794730092,
  "exp": 1794730392
}
```

Show the times as dates:

```bash
./jwt-decode.sh "$TOKEN" | jq -s '.[1] | {iat: (.iat|todate), exp: (.exp|todate)}'
```

- **Expected:** `exp` is 5 minutes after `iat`, in UTC (`...Z`).

| Claim | Meaning |
| --- | --- |
| `iss` | Issuer: who made the token |
| `sub` | Subject: who the token is about (here the client program) |
| `aud` | Audience: which API the token is for |
| `iat` | Issued at (seconds since 1970, UTC) |
| `nbf` | Not before: invalid until this time |
| `exp` | Expiry: invalid from this time |

- **Why:** anyone can read a JWT. Never put passwords or card numbers in a payload. The **signature** only proves nobody changed it.

## 4. Verify the signature, then tamper with one character

- `check-jwt.py` verifies a token with PyJWT: signature, `exp`, `nbf`, `iat`, `iss` and `aud`.

Read the checker:

```bash
cat check-jwt.py
```

Check the good token:

```bash
python3 check-jwt.py "$TOKEN"
```

- **Expected:** `VALID: {'iss': 'https://auth.example.com', 'sub': 'mobile-app', 'aud': 'payment-api', ...}`

Change one character of the payload (`mobile-app` becomes `mobile-apq`), keep the old signature:

```bash
FORGED=$(echo "$TOKEN" | sed 's/UtYXBw/UtYXBx/')
```

Decode the forged token:

```bash
./jwt-decode.sh "$FORGED"
```

Check it:

```bash
python3 check-jwt.py "$FORGED"
```

- **Expected:** decode shows `"sub": "mobile-apq"`; the checker says:

```text
REJECTED: InvalidSignatureError - Signature verification failed
```

- **Why:** the signature is calculated over `header.payload`. Change one byte and it no longer matches; without the key nobody can make a new one.

## 5. RS256 — sign with a private key, check with a public key

- HS256 needs the **same secret** on the signer and on every checker; any checker could also sign.
- RS256 uses a **key pair**: the issuer signs with the **private** key; gateways and apps check with the **public** key, which cannot sign.

Create the issuer folder:

```bash
mkdir -p ~/lab/security/issuer
```

Generate a 2048-bit RSA private key:

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ~/lab/security/issuer/private.pem
```

Make it readable by you only:

```bash
chmod 600 ~/lab/security/issuer/private.pem
```

Extract the public key:

```bash
openssl pkey -in ~/lab/security/issuer/private.pem -pubout -out ~/lab/security/issuer/public.pem
```

Compare the two files:

```bash
ls -l ~/lab/security/issuer
```

Show the public key (safe to share):

```bash
cat ~/lab/security/issuer/public.pem
```

- **Expected:** `private.pem` is `-rw-------`; `public.pem` starts with `-----BEGIN PUBLIC KEY-----`. (The dots and `+` signs printed by `genpkey` are normal progress output.)

Make an RS256 token with the private key:

```bash
RTOKEN=$(ALG=RS256 ./make-jwt.sh 300)
```

Read its header:

```bash
./jwt-decode.sh "$RTOKEN"
```

Check it with the public key:

```bash
python3 check-jwt.py "$RTOKEN"
```

- **Expected:** header `"alg": "RS256"`; `VALID: ...`. The RS256 signature part is much longer (256 bytes) than HS256 (32 bytes).

| | HS256 | RS256 |
| --- | --- | --- |
| Signs with | shared secret | private key (issuer only) |
| Checks with | same shared secret | public key (anyone) |
| A checker can forge tokens? | yes | no |

## 6. Run a tiny OAuth 2.0 token issuer

- Real systems get tokens from an authorization server. `issuer.py` is a small one: **client credentials** grant (one program logs in as itself), RS256 tokens valid 300 seconds, signed with **your** private key.
- Client: `mobile-app` / `mobile-secret-456` (classroom only).

Read the issuer:

```bash
cat issuer.py
```

**Terminal B** — go to the folder:

```bash
cd ~/ltm/middleware-labs-day2/project-files/security
```

**Terminal B** — start the issuer (leave it running; Ctrl+C stops it):

```bash
python3 issuer.py
```

- **Expected:** `Token issuer listening on http://127.0.0.1:9000/token`; each request then prints one log line here.

**Terminal A** — check the listener:

```bash
sudo ss -lntp 'sport = :9000'
```

Ask for a token:

```bash
curl -s -X POST http://127.0.0.1:9000/token -d grant_type=client_credentials -d client_id=mobile-app -d client_secret=mobile-secret-456 | jq .
```

- **Expected:** `127.0.0.1:9000` owned by `python3`, then:

```text
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOi...",
  "token_type": "Bearer",
  "expires_in": 300
}
```

Wrong client secret:

```bash
curl -i -X POST http://127.0.0.1:9000/token -d grant_type=client_credentials -d client_id=mobile-app -d client_secret=wrong
```

Unsupported grant type:

```bash
curl -i -X POST http://127.0.0.1:9000/token -d grant_type=password -d client_id=mobile-app -d client_secret=mobile-secret-456
```

- **Expected:** `HTTP/1.0 401 Unauthorized` with `{"error": "invalid_client"}`, then `HTTP/1.0 400 Bad Request` with `{"error": "unsupported_grant_type"}`.

Keep a fresh access token in a variable:

```bash
ACCESS=$(curl -s -X POST http://127.0.0.1:9000/token -d grant_type=client_credentials -d client_id=mobile-app -d client_secret=mobile-secret-456 | jq -r .access_token)
```

Decode it:

```bash
./jwt-decode.sh "$ACCESS"
```

- **Expected:** `"alg": "RS256"`, the six claims from step 3 plus a `jti` (unique token id).
- **If it fails** with `curl: (7) Failed to connect to 127.0.0.1 port 9000 ... Couldn't connect to server`: the issuer is not running in Terminal B.
- Tokens expire after 5 minutes — repeat the `ACCESS=...` command whenever a later step needs a fresh one.

## 7. Protect a new Kong route with the JWT plugin

- Stage 5 = Day 1 stage 4 unchanged, plus service `payment-v2`, route `/api/v2/payment`, the `jwt` plugin on that service, and the issuer public key on consumer `mobile-app`.
- Kong finds the consumer from the token's `iss` claim (`key_claim_name: iss`) and checks the RS256 signature and `exp` (`claims_to_verify: [exp]`).

Read the stage file (note the placeholder line):

```bash
cat ~/ltm/middleware-labs-day2/project-files/kong/05-jwt.yml
```

Read the script that puts your public key in place of the placeholder:

```bash
cat fill-kong-key.sh
```

Make your copy of stage 5:

```bash
./fill-kong-key.sh
```

Check your public key is in it:

```bash
grep -A3 'rsa_public_key' ~/lab/security/05-jwt.yml
```

Save the current Kong file (Day 1 stage 4):

```bash
sudo cp /etc/kong-lab/kong.yml ~/lab/backups/kong-day1-stage4.yml
```

Install stage 5:

```bash
sudo cp ~/lab/security/05-jwt.yml /etc/kong-lab/kong.yml
```

Validate, then reload:

```bash
sudo -u kong-lab kong config parse /etc/kong-lab/kong.yml -c /etc/kong-lab/kong.conf && sudo systemctl reload payment-kong
```

Wait for the new workers:

```bash
sleep 5
```

- **Expected:** `parse successful` (the `ulimit` warning is harmless).
- **If it fails** with `in 'rsa_public_key': invalid key`: you installed the raw stage file with the placeholder. Run `./fill-kong-key.sh` and install `~/lab/security/05-jwt.yml`.

No token:

```bash
curl -i http://127.0.0.1:8000/api/v2/payment/status
```

A token that is not a JWT:

```bash
curl -i -H 'Authorization: Bearer not-a-real-token' http://127.0.0.1:8000/api/v2/payment/status
```

A fresh token from the issuer:

```bash
ACCESS=$(curl -s -X POST http://127.0.0.1:9000/token -d grant_type=client_credentials -d client_id=mobile-app -d client_secret=mobile-secret-456 | jq -r .access_token)
```

Call the new route with it:

```bash
curl -i -H "Authorization: Bearer $ACCESS" http://127.0.0.1:8000/api/v2/payment/status
```

An RS256 token, correctly signed, that expired 60 seconds ago:

```bash
curl -i -H "Authorization: Bearer $(ALG=RS256 ./make-jwt.sh -60)" http://127.0.0.1:8000/api/v2/payment/status
```

The tampered token (one character changed):

```bash
curl -i -H "Authorization: Bearer $(echo "$ACCESS" | sed 's/UtYXBw/UtYXBx/')" http://127.0.0.1:8000/api/v2/payment/status
```

| Test | Status | Kong body | `WWW-Authenticate` |
| --- | --- | --- | --- |
| No token | 401 | `{"message":"Unauthorized"}` | `Bearer` |
| Not a JWT | 401 | `{"message":"Bad token; invalid JSON"}` | `Bearer error="invalid_token"` |
| Valid issuer token | 200 | `Payment Service OK` | — |
| Expired token | 401 | `{"exp":"token expired"}` | `Bearer error="invalid_token"` |
| Tampered token | 401 | `{"message":"Invalid signature"}` | `Bearer error="invalid_token"` |

- An HS256 token from step 3 is refused with `{"message":"Invalid algorithm"}`: the consumer only accepts RS256.

The Day 1 API key on the new route:

```bash
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/v2/payment/status
```

The Day 1 route with the Day 1 key:

```bash
curl -i -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

- **Expected:** `401 {"message":"Unauthorized"}` (the new route wants a token, not a key), then `200 Payment Service OK` with the Day 1 `X-RateLimit-Remaining-Minute` header — stage 4 still works.
- A 429 on the Day 1 route means you used the 5 calls of this minute; wait for the next minute.

Save evidence:

```bash
sudo tail -n 8 /var/log/kong-lab/access.log | tee ~/lab/evidence/day2/lab3-kong-jwt.txt
```

## 8. What Kong's JWT plugin does NOT check

- Kong checked the signature, the issuer (to find the consumer) and `exp`. Prove what it lets through.

A valid signature but the wrong audience (`other-api`):

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(ALG=RS256 ./make-jwt.sh 300 other-api)" http://127.0.0.1:8000/api/v2/payment/status
```

A token that only becomes valid in 10 minutes (`nbf` in the future):

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $(ALG=RS256 ./make-jwt.sh 3600 payment-api 600)" http://127.0.0.1:8000/api/v2/payment/status
```

Get a fresh token:

```bash
ACCESS=$(curl -s -X POST http://127.0.0.1:9000/token -d grant_type=client_credentials -d client_id=mobile-app -d client_secret=mobile-secret-456 | jq -r .access_token)
```

Send it in the URL instead of the header:

```bash
curl -s "http://127.0.0.1:8000/api/v2/payment/status?jwt=$ACCESS"
```

Look at Kong's access log:

```bash
sudo tail -n 1 /var/log/kong-lab/access.log
```

- **Expected:** `200`, `200`, `Payment Service OK`, and the whole token written in the log line:

```text
127.0.0.1 - - [15/Nov/2026:08:09:22 +0000] "GET /api/v2/payment/status?jwt=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3Mi...
```

| Gap | Risk | Fix |
| --- | --- | --- |
| `aud` not checked | a token meant for another API works here | the app (or a stricter gateway plugin) checks `aud` |
| `nbf` not checked | a token used before its start time | `claims_to_verify: [ exp, nbf ]` |
| `?jwt=` accepted | tokens land in access logs, browser history, proxies | `uri_param_names: []`; send tokens only in the `Authorization` header |

- Anyone who can read the log can now reuse that token until it expires. Treat logs that hold tokens as secrets.

## 9. Validate claims properly in the application (PyJWT)

- `check-jwt.py` asks PyJWT to check everything, the way the payment application should.

Wrong audience:

```bash
python3 check-jwt.py "$(ALG=RS256 ./make-jwt.sh 300 other-api)"
```

Expired 60 seconds ago:

```bash
python3 check-jwt.py "$(ALG=RS256 ./make-jwt.sh -60)"
```

Not valid for another 10 minutes:

```bash
python3 check-jwt.py "$(ALG=RS256 ./make-jwt.sh 3600 payment-api 600)"
```

Tampered:

```bash
python3 check-jwt.py "$(echo "$ACCESS" | sed 's/UtYXBw/UtYXBx/')"
```

- **Expected:**

```text
REJECTED: InvalidAudienceError - Audience doesn't match
REJECTED: ExpiredSignatureError - Signature has expired
REJECTED: ImmatureSignatureError - The token is not yet valid (iat)
REJECTED: InvalidSignatureError - Signature verification failed
```

- The third message says `(iat)` because the script sets `iat` and `nbf` to the same future time and PyJWT checks `iat` first; the error type is the same for `nbf`.

| Exception | Cause |
| --- | --- |
| `InvalidSignatureError` | payload or header changed, or wrong key |
| `ExpiredSignatureError` | now is after `exp` |
| `ImmatureSignatureError` | now is before `nbf` (or `iat`) |
| `InvalidAudienceError` | `aud` is not this API |

## 10. Clock skew — why a small leeway helps

- Every check above compares token times with **this** machine's clock. If the issuer's clock and yours differ, good tokens fail.
- Do **not** change the system clock in the lab; simulate a wrong issuer clock with the token times instead.

Show this machine's clock and time sync:

```bash
timedatectl
```

- **Expected** on a normal laptop: `System clock synchronized: yes` and `NTP service: active`. A machine without time sync shows:

```text
System clock synchronized: no
              NTP service: inactive
```

An issuer whose clock is 30 seconds ahead (`iat`/`nbf` 30 s in the future):

```bash
python3 check-jwt.py "$(ALG=RS256 ./make-jwt.sh 300 payment-api 30)"
```

The same, allowing 60 seconds of leeway:

```bash
python3 check-jwt.py "$(ALG=RS256 ./make-jwt.sh 300 payment-api 30)" 60
```

A token that expired 20 seconds ago, with 60 seconds of leeway:

```bash
python3 check-jwt.py "$(ALG=RS256 ./make-jwt.sh -20)" 60
```

A token that expired 2 minutes ago, with 60 seconds of leeway:

```bash
python3 check-jwt.py "$(ALG=RS256 ./make-jwt.sh -120)" 60
```

- **Expected:** `ImmatureSignatureError`, then `VALID`, `VALID`, and `ExpiredSignatureError - Signature has expired`.
- **Why:** leeway forgives small clock differences (30–60 s is common). Keep it small: a large leeway keeps expired tokens alive. The real fix for big differences is NTP on every server.

## 11. Build your own certificate chain

- A server certificate is trusted because a **CA** signed it. Real chains have three levels: **root CA** (in the trust store) → **intermediate CA** (signs servers) → **server certificate**.
- `make-ca.sh` builds that chain for `portal.example.test`, with the name in the **SAN** (subjectAltName).

Read the script:

```bash
cat make-ca.sh
```

Build the chain:

```bash
./make-ca.sh
```

Go to the new folder:

```bash
cd ~/lab/security/pki
```

Inspect the root:

```bash
openssl x509 -in root.crt -noout -subject -issuer -dates
```

Inspect the intermediate:

```bash
openssl x509 -in int.crt -noout -subject -issuer -dates
```

Inspect the server certificate:

```bash
openssl x509 -in server.crt -noout -subject -issuer -dates -ext subjectAltName
```

- Sample output (server):

```text
subject=CN = portal.example.test
issuer=CN = PayBank Lab Issuing CA 1
notBefore=Nov 15 08:09:34 2026 GMT
notAfter=Feb 13 08:09:34 2027 GMT
X509v3 Subject Alternative Name:
    DNS:portal.example.test
```

- The root's subject and issuer are the same (it signs itself); each other issuer is the subject one level up.

Verify the chain with the intermediate:

```bash
openssl verify -CAfile root.crt -untrusted int.crt server.crt
```

Verify without the intermediate:

```bash
openssl verify -CAfile root.crt server.crt
```

- **Expected:** `server.crt: OK`, then `error 20 at 0 depth lookup: unable to get local issuer certificate`.
- **Why:** the root alone cannot link to the server certificate; the intermediate is the missing link. Remember this for step 14.

Go back to the scripts folder:

```bash
cd ~/ltm/middleware-labs-day2/project-files/security
```

## 12. Serve the portal over HTTPS with Nginx on port 443

- Nginx sends `fullchain.crt` (server certificate, then intermediate) and keeps the private key readable by root only.

Create the certificate folder:

```bash
sudo install -d -m 755 /etc/nginx/ssl
```

Install the chain:

```bash
sudo install -m 644 ~/lab/security/pki/fullchain.crt /etc/nginx/ssl/portal-chain.crt
```

Install the private key:

```bash
sudo install -m 600 ~/lab/security/pki/server.key /etc/nginx/ssl/portal.key
```

Read the HTTPS site:

```bash
cat nginx-tls.conf
```

Install it:

```bash
sudo cp nginx-tls.conf /etc/nginx/sites-available/payment-tls
```

Enable it:

```bash
sudo ln -sfn /etc/nginx/sites-available/payment-tls /etc/nginx/sites-enabled/payment-tls
```

Test, then reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Check port 443:

```bash
sudo ss -lntp 'sport = :443'
```

Call the portal, trusting your root CA for this one command:

```bash
curl -i --cacert ~/lab/security/pki/root.crt https://portal.example.test/health.txt
```

Call the payment service through HTTPS:

```bash
curl -s --cacert ~/lab/security/pki/root.crt https://portal.example.test/payment/status
```

- **Expected:** `syntax is ok` / `test is successful`, Nginx on `0.0.0.0:443`, `HTTP/1.1 200 OK` with `WEB PORTAL OK`, then `Payment Service OK`.

Watch curl check the certificate:

```bash
curl -v --cacert ~/lab/security/pki/root.crt -o /dev/null https://portal.example.test/health.txt
```

- Sample lines:

```text
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / X25519 / RSASSA-PSS
*  subject: CN=portal.example.test
*  expire date: Feb 13 08:09:34 2027 GMT
*  subjectAltName: host "portal.example.test" matched cert's "portal.example.test"
*  issuer: CN=PayBank Lab Issuing CA 1
*  SSL certificate verify ok.
```

Show the certificates the server sends:

```bash
openssl s_client -connect portal.example.test:443 -servername portal.example.test -showcerts -CAfile ~/lab/security/pki/root.crt </dev/null
```

- **Expected:** a `Certificate chain` with two entries, and `Verify return code: 0 (ok)`:

```text
 0 s:CN = portal.example.test
   i:CN = PayBank Lab Issuing CA 1
 1 s:CN = PayBank Lab Issuing CA 1
   i:CN = PayBank Lab Root CA
```

- `s:` = subject, `i:` = issuer. The server never sends the root: the client must already have it.

Call without `--cacert`:

```bash
curl -I https://portal.example.test/health.txt
```

- **Expected:** `curl: (60) SSL certificate problem: unable to get local issuer certificate` — your laptop does not trust your private root yet.

## 13. Trust your root CA system-wide, then remove it

- Ubuntu tools (curl, wget, Python, Java via `ca-certificates-java`) read the system trust store in `/etc/ssl/certs`.

Add the root:

```bash
sudo cp ~/lab/security/pki/root.crt /usr/local/share/ca-certificates/paybank-lab-root.crt
```

Rebuild the trust store:

```bash
sudo update-ca-certificates
```

Plain curl, no `--cacert`:

```bash
curl -s https://portal.example.test/health.txt
```

- **Expected:** `1 added, 0 removed; done.`, a line `Adding debian:paybank-lab-root.pem` (Java's store too), then `WEB PORTAL OK`.

Remove the root again (a lab CA should not stay trusted):

```bash
sudo rm /usr/local/share/ca-certificates/paybank-lab-root.crt
```

Rebuild the trust store from scratch:

```bash
sudo update-ca-certificates --fresh
```

Plain curl again:

```bash
curl -sS https://portal.example.test/health.txt
```

- **Expected:** a long list of `Replacing debian:...` lines including `Removing debian:paybank-lab-root.pem` (Java's store too), then `curl: (60) SSL certificate problem: unable to get local issuer certificate`.
- Use `--fresh` here: a plain `update-ca-certificates` after the `rm` prints `0 added, 0 removed` and leaves the root in Java's store.
- **Why:** adding a root means trusting **every** certificate that CA signs. Do it only for CAs your organisation controls.

## 14. Fault exercises — four certificate errors

- Each break swaps the file Nginx serves. After each `reload`, if you still see the old result, wait two seconds and repeat the curl.

### A. Missing intermediate

**Break** — serve the server certificate alone:

```bash
sudo cp ~/lab/security/pki/server.crt /etc/nginx/ssl/portal-chain.crt
```

Test, then reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Observe** — call the portal:

```bash
curl --cacert ~/lab/security/pki/root.crt https://portal.example.test/health.txt
```

Show what the server sends:

```bash
openssl s_client -connect portal.example.test:443 -servername portal.example.test -showcerts -CAfile ~/lab/security/pki/root.crt </dev/null
```

- **Expected:** `curl: (60) SSL certificate problem: unable to get local issuer certificate`; the chain shows only entry `0`, and `Verify return code: 21 (unable to verify the first certificate)`.
- `nginx -t` passes: the file is a valid certificate, just an incomplete chain. Some browsers hide this fault by fetching the intermediate themselves; curl, Java and most API clients do not.

**Recover** — put the full chain back:

```bash
sudo cp ~/lab/security/pki/fullchain.crt /etc/nginx/ssl/portal-chain.crt
```

Test, then reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Verify:**

```bash
curl --cacert ~/lab/security/pki/root.crt https://portal.example.test/health.txt
```

- **Expected:** `WEB PORTAL OK`.

### B. Expired certificate

**Break** — read the script that signs the same request with past dates:

```bash
cat make-expired.sh
```

Run it:

```bash
./make-expired.sh
```

Serve the expired chain:

```bash
sudo cp ~/lab/security/pki/expired-fullchain.crt /etc/nginx/ssl/portal-chain.crt
```

Test, then reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Observe** — call the portal:

```bash
curl --cacert ~/lab/security/pki/root.crt https://portal.example.test/health.txt
```

Read the dates of the certificate the server sends:

```bash
openssl s_client -connect portal.example.test:443 -servername portal.example.test </dev/null 2>/dev/null | openssl x509 -noout -dates
```

- **Expected:** the script prints dates 60 and 30 days ago; `curl: (60) SSL certificate problem: certificate has expired`; `notAfter` is in the past.
- `s_client` alone reports `Verify return code: 10 (certificate has expired)`. Nginx starts happily with an expired certificate — only clients notice.

**Recover** — put the full chain back:

```bash
sudo cp ~/lab/security/pki/fullchain.crt /etc/nginx/ssl/portal-chain.crt
```

Test, then reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Verify:**

```bash
curl --cacert ~/lab/security/pki/root.crt https://portal.example.test/health.txt
```

### C. Wrong host name

**Break** — call the server by a name that is not in the certificate:

```bash
curl --cacert ~/lab/security/pki/root.crt https://localhost/health.txt
```

**Observe** — ask openssl to check the name too:

```bash
openssl s_client -connect localhost:443 -verify_hostname localhost -CAfile ~/lab/security/pki/root.crt </dev/null
```

- **Expected:** `curl: (60) SSL: no alternative certificate subject name matches target host name 'localhost'` and `Verify return code: 62 (hostname mismatch)`. A `Can't use SSL_get_servername` line from openssl is harmless.
- **Why:** the chain is fine; the **name** the client used is not in the SAN list.

**Recover** — use a name that is in the SAN (or issue a new certificate that lists every name clients use):

```bash
openssl x509 -in ~/lab/security/pki/server.crt -noout -ext subjectAltName
```

**Verify:**

```bash
curl --cacert ~/lab/security/pki/root.crt https://portal.example.test/health.txt
```

### D. Untrusted root

**Break** — the client does not have your root (plain curl uses only the system store):

```bash
curl https://portal.example.test/health.txt
```

**Observe** — show what the server sends, checked against the system store:

```bash
openssl s_client -connect portal.example.test:443 -servername portal.example.test -showcerts </dev/null
```

- **Expected:** `curl: (60) SSL certificate problem: unable to get local issuer certificate` — the **same** curl error as fault A. But now the chain has **two** entries and `Verify return code: 20 (unable to get local issuer certificate)`.
- **Why:** A = the server sent too little (fix the server). D = the client trusts too little (fix the client's trust store). `-showcerts` tells you which.

**Recover / Verify** — give the client the root:

```bash
curl --cacert ~/lab/security/pki/root.crt https://portal.example.test/health.txt
```

| curl error | Likely cause | Who fixes it |
| --- | --- | --- |
| `unable to get local issuer certificate`, 1 cert sent | missing intermediate | server team |
| `unable to get local issuer certificate`, 2 certs sent | client does not trust the root | client team |
| `certificate has expired` | expired server certificate | server team (renew) |
| `no alternative certificate subject name matches` | name not in SAN | client uses right name, or reissue |

## 15. Java has its own trust store

- Java applications (Tomcat, Kafka clients, Spring apps) usually trust Java's `cacerts`, not what you pass to curl.

Read the Java check:

```bash
cat TlsCheck.java
```

Run it (Java compiles and runs a single file):

```bash
java TlsCheck.java https://portal.example.test/health.txt
```

- **Expected:** a stack trace starting:

```text
Exception in thread "main" javax.net.ssl.SSLHandshakeException: (certificate_unknown) PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
```

- **If `java` cannot run a `.java` file:** install `openjdk-21-jdk-headless` (Day 2 start); the JRE alone has no compiler.

Create a truststore that holds only your root:

```bash
keytool -importcert -noprompt -alias paybank-lab-root -file ~/lab/security/pki/root.crt -keystore ~/lab/security/pki/lab-truststore.p12 -storetype PKCS12 -storepass changeit
```

List it:

```bash
keytool -list -keystore ~/lab/security/pki/lab-truststore.p12 -storepass changeit
```

Run Java with that truststore:

```bash
java -Djavax.net.ssl.trustStore=$HOME/lab/security/pki/lab-truststore.p12 -Djavax.net.ssl.trustStorePassword=changeit TlsCheck.java https://portal.example.test/health.txt
```

- **Expected:** `Certificate was added to keystore`, `Your keystore contains 1 entry`, then `200 WEB PORTAL OK`.
- With this truststore the same Java check reports the other faults as `PKIX path validation failed: ... validity check failed` (expired) and `No subject alternative DNS name matching localhost found.` (wrong name).
- **Why:** a store with only your root trusts nothing else (no public websites). Real services usually import the company root into a copy of `cacerts` instead.

## 16. Watch expiry and plan renewal

- Expired certificates are a common, fully preventable outage. Check ahead with `-checkend <seconds>`.

Expiry date of the server certificate:

```bash
openssl x509 -in ~/lab/security/pki/server.crt -noout -enddate
```

Will it still be valid in 30 days?

```bash
openssl x509 -in ~/lab/security/pki/server.crt -noout -checkend 2592000
```

Will it still be valid in 100 days?

```bash
openssl x509 -in ~/lab/security/pki/server.crt -noout -checkend 8640000
```

- **Expected:** `Certificate will not expire` (exit 0), then `Certificate will expire` (exit 1) — the certificate is valid for 90 days only.

Check what the live server actually sends:

```bash
openssl s_client -connect portal.example.test:443 -servername portal.example.test </dev/null 2>/dev/null | openssl x509 -noout -subject -enddate -checkend 2592000
```

- **Expected:** `subject=CN = portal.example.test`, its `notAfter=` date, `Certificate will not expire`.
- **Why:** check the **live** endpoint, not only the file: a reload that never happened means the old certificate is still served. Monitoring tools run this kind of check daily and alert at 30 and 14 days.

Renewal checklist:

- Make a new key and CSR (or reuse the CSR only if policy allows); keep the same SAN names, and add any new ones.
- Get it signed; build the new `fullchain.crt` (server first, then intermediate).
- Check the key matches the certificate: `openssl x509 -noout -modulus -in server.crt | openssl sha256` equals `sudo openssl rsa -noout -modulus -in <key> | openssl sha256`.
- Back up the old files, install the new ones, `sudo nginx -t`, then reload.
- Verify the live endpoint: `-dates`, `-showcerts` (two certificates), `curl` with no errors.
- Update Java truststores and partners if the CA chain changed. Record the new expiry date and set the next reminder.

## 17. Handoff

- Kong stage 5 and Nginx 443 stay in place. The token issuer is only needed in this lab.

**Terminal B** — stop the issuer with Ctrl+C.

Check the services:

```bash
systemctl is-active apache2 nginx tomcat payment-kong
```

Check Kong's health:

```bash
sudo -u kong-lab kong health -p /var/lib/kong-lab
```

Day 1 route with the API key:

```bash
curl -s -H 'apikey: demo-key-123' http://127.0.0.1:8000/api/payment/status
```

New route without a token:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/api/v2/payment/status
```

HTTPS portal:

```bash
curl -s --cacert ~/lab/security/pki/root.crt https://portal.example.test/health.txt
```

Listeners:

```bash
sudo ss -lntp '( sport = :443 or sport = :8000 or sport = :9000 )'
```

Save evidence:

```bash
openssl x509 -in ~/lab/security/pki/server.crt -noout -subject -issuer -enddate | tee ~/lab/evidence/day2/lab3-tls.txt
```

- **Expected:** four `active`, Kong healthy, `Payment Service OK`, `401`, `WEB PORTAL OK`; listeners on `0.0.0.0:443` and `127.0.0.1:8000` (both shown as `nginx`: Kong runs on Nginx), nothing on 9000.
- To go back to Day 1 stage 4: `sudo cp ~/lab/backups/kong-day1-stage4.yml /etc/kong-lab/kong.yml`, then parse and reload as in step 7.
- Never copy `~/lab/security/` into Git: it holds private keys.

## Check yourself

1. Apache answered 401 with `WWW-Authenticate: Basic`, and Kong answered 403 for `blocked-partner`. Which one is an authentication failure, which one an authorization failure, and why?
2. Why is the `Authorization: Basic ...` header not a secret, and what protects it?
3. You change one letter of a JWT payload and keep the signature. What does Kong answer, and why can't the attacker just compute a new signature for RS256?
4. Name the claims `iss`, `aud`, `exp`, `nbf` in plain words. Which of them did Kong check in this lab, and which did it let through?
5. Why do gateways and applications get the issuer's **public** key and not the private key? What goes wrong if many services share one HS256 secret?
6. A token is rejected with `ImmatureSignatureError` on one server only. What is the likely cause, what is the quick fix, and what is the real fix?
7. Two clients both see `curl: (60) SSL certificate problem: unable to get local issuer certificate`. How do you tell "missing intermediate" from "untrusted root", and which team fixes each?
8. curl with `--cacert` works but a Java client fails with `PKIX path building failed`. Why, and what are two ways to fix it?
