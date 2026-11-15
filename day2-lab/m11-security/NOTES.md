# Module 11 · Authentication and API security — builder notes

65 slides (`order-m11.txt`), generator `gen2/m11.py`, lab files used for testing in `lab/`.
Timing: about 80–85 min of teaching incl. 12 short try-its (2–5 min each), plus the 40-min lab.

## Versions tested (container d2-m11, image mw-ubuntu-test:24.04, arm64)
- Ubuntu 24.04, curl 8.5.0 (OpenSSL/3.0.13), OpenSSL 3.0.13, Apache 2.4.58, Nginx 1.24.0
- Kong Gateway OSS **3.9.1** (deb from packages.konghq.com gateway-39, noble), DB-less
- PyJWT **2.7.0** (`python3-jwt` Ubuntu package), python3-cryptography
- OpenJDK 21.0.x (`openjdk-21-jdk-headless` needed for `java File.java` single-file launch; the JRE alone cannot do it)
- Backend: a tiny Python stub on 127.0.0.1:8080 answering "Payment Service OK" stood in for Tomcat/payment.war. Slides show Day 1 URLs. Kong 200 responses therefore carried `Server: BaseHTTP…` headers; those headers are not shown on slides.

## Verified for real (output on slides captured)
- Apache Basic: 401 + `WWW-Authenticate: Basic realm="Admins only"`, `Authorization: Basic YWRtaW46czNjcmV0`, base64 -d, AH01617 Password Mismatch.
- Kong key-auth: `WWW-Authenticate: Key`, "No API key found in request"; wrong key → body `{"message":"Unauthorized"}` (3.9.1).
- Token issuer (`issuer.py`, client-credentials only, RS256, JWKS at /.well-known/jwks.json, port 9000): 200 JSON, 401 invalid_client, 400 unsupported_grant_type.
- HS256 JWT built in bash (`make-jwt.sh`) and decoded (`jwt-decode.sh`, basenc --base64url); plain `base64 -d` prints "base64: invalid input".
- Kong jwt plugin bodies: Unauthorized; Bad token; invalid JSON; Bad token; invalid alg (alg none); No credentials found for given 'iss'; Invalid signature; Invalid algorithm; {"exp":"token expired"}; {"exp":"exceeds maximum allowed expiration"}; {"nbf":"token not valid yet"}; {"nbf":"must be a number"} (nbf listed, token without nbf). `WWW-Authenticate: Bearer` / `Bearer error="invalid_token"`.
- Kong gaps verified: wrong `aud` → 200; future `iat` → 200; no `claims_to_verify` → expired token 200; `?jwt=` accepted and logged in access.log; `uri_param_names: []` turns that off.
- PyJWT messages: ExpiredSignatureError "Signature has expired", InvalidAudienceError "Audience doesn't match" (and "Invalid audience" when decode() has no audience=), InvalidIssuerError, InvalidSignatureError, ImmatureSignatureError (nbf)/(iat), InvalidAlgorithmError, DecodeError "Not enough segments", MissingRequiredClaimError; leeway works.
- RS256 end to end: issuer token → Kong with `rsa_public_key` → 200; HS256 token → Invalid algorithm; same token after 301 s → token expired.
- **Kong oauth2 plugin in DB-less**: `kong config parse` says OK, but POST https://localhost:8443/…/oauth2/token → 500 "An unexpected error occurred"; error.log: `cannot create 'oauth2_tokens' entities when not using a database`. So "configure OAuth" = our issuer + Kong jwt as resource server. Stated on m11-oauth-lab.
- TLS: own root → intermediate → server chain with openssl (ext-file variant re-run and verified), Nginx on **443**, curl -v, s_client -showcerts, curl (60) unable to get local issuer certificate / certificate has expired / no alternative certificate subject name matches; s_client verify 20, 21, 10; update-ca-certificates (also updates Java cacerts via ca-certificates-java); Nginx 400 "plain HTTP request was sent to HTTPS port"; curl (35) wrong version number; key mismatch `SSL_CTX_use_PrivateKey … key values mismatch`; -checkend; Java 21 PKIX path building failed / validity check failed / No subject alternative DNS name matching; keytool -list (120 entries) and -importcert; -Djavax.net.ssl.trustStore → 200.

## Not verified / simulated
- `sudo timedatectl set-ntp true` not run (container shows "System clock synchronized: no / NTP service: inactive" — that real output is shown as the bad state).
- Authorization-code flow is a picture only (no browser/login server).
- Spring Security's 60 s default clock skew is from documentation, not tested.
- `ssh auth-server date -u` is a command pattern, not run.
- "Works in browser" for a missing intermediate is explained (cache/AIA), not demonstrated in a browser.
- Kong reload in DB-less took 5–20 s to apply on the heavily loaded test host; slides tell students to wait a few seconds.

## Facts other modules must stay consistent with
- **Port 8443 is taken by Kong** (default proxy_listen includes 8443 ssl; 8444 = admin ssl). Nginx HTTPS therefore uses **443** (`/etc/nginx/sites-available/payment-tls`, certs in `/etc/nginx/ssl/`). Apache ssl not enabled.
- New status code introduced here: **400 Bad Request** (token endpoint unsupported_grant_type; Nginx plain-HTTP-to-HTTPS-port). 401 now always shown with its WWW-Authenticate header (Basic / Key / Bearer).
- Kong additions: service `payment-v2`, route `/api/v2/payment`, plugin `jwt` (`claims_to_verify: [ exp ]`), consumer `mobile-app` gets `jwt_secrets` key `https://auth.example.com` (HS256 secret `paybank-lab-secret-do-not-reuse-1`, later RS256 + rsa_public_key). Day 1 route `/api/payment` with key-auth + rate-limiting untouched. Backups: `/etc/kong/kong.yml.day1`, `.hs256`.
- Token issuer: `~/lab/issuer/issuer.py` on 127.0.0.1:9000, client `mobile-app` / `mobile-secret-456`, iss `https://auth.example.com`, aud `payment-api`, scope `payments:read`, 300 s, kid `lab-key-1`.
- PKI: `~/lab/pki` (root "PayBank Lab Root CA", intermediate "PayBank Lab Issuing CA 1", server `payment.example.com`, 90 days); `/etc/hosts` maps payment.example.com → 127.0.0.1.
- Lab bundle files needed (copies in `lab/`): make-jwt.sh, make-jwt-future.sh, jwt-decode.sh, check-jwt.py, issuer/ (issuer.py, private.pem, public.pem), kong-jwt.yml, kong-rs256.yml, make-ca.sh, make-expired.sh, payment-tls, java/TlsCheck.java. VM needs `python3-jwt jq` and `openjdk-21-jdk-headless`.
