# Lab 3 — Security: Check yourself answers

1. **401 vs 403.** Apache's 401 is an authentication failure: it does not know who you are yet, and `WWW-Authenticate: Basic` asks for credentials. Kong's 403 for `blocked-partner` is an authorization failure: the API key was valid (Kong knows the caller), but the ACL plugin does not allow that consumer's group on this service.

2. **Basic auth header.** `Authorization: Basic ...` is only base64 of `user:password`; `base64 -d` turns it back into plain text. Base64 is encoding, not encryption. Only TLS (HTTPS) protects it on the wire; it can still leak through logs or debugging output, so treat it as a password.

3. **Tampered JWT.** Kong answers `401` with `{"message":"Invalid signature"}` (PyJWT: `InvalidSignatureError`). The signature covers `header.payload`; changing one byte breaks it. With RS256 a new valid signature needs the issuer's private key, which only the issuer has — gateways and apps hold only the public key, which can check but not sign.

4. **Claims.** `iss` = who issued the token; `aud` = which API it is meant for; `exp` = expiry time; `nbf` = not valid before this time. Kong (stage 5) used `iss` to find the consumer and its key, checked the signature and `exp`. It let through a wrong `aud`, a future `nbf`, and a token sent in the URL (`?jwt=`), which also ended up in the access log.

5. **Public key, not private.** The private key can create tokens; anyone holding it can impersonate the issuer, so only the issuer keeps it. Verifiers need only the public key. With one shared HS256 secret, every service that can check tokens can also forge them, and a leak from any one service compromises all of them; rotating the secret means changing every service at once.

6. **`ImmatureSignatureError` on one server.** That server's clock is behind the issuer's (or the issuer's is ahead), so `iat`/`nbf` look like they are in the future. Quick fix: a small leeway (30–60 s) in the validator. Real fix: time sync (NTP) on every server — check with `timedatectl` (`System clock synchronized: yes`, `NTP service: active`). Never use a large leeway: it keeps expired tokens alive.

7. **Missing intermediate vs untrusted root.** Run `openssl s_client -connect host:443 -servername host -showcerts`. Missing intermediate: the chain lists only certificate `0` and the result is `Verify return code: 21 (unable to verify the first certificate)` even with the right root — the **server** team must send `fullchain` (server + intermediate). Untrusted root: the chain has two certificates (server + intermediate) and `Verify return code: 20` — the **client** team must add the root CA to the client's trust store (or pass it with `--cacert`).

8. **curl works, Java fails with PKIX.** `--cacert` only affects that curl command; Java uses its own trust store (`cacerts`) which does not contain the lab root, so it cannot build a path to a trusted root. Fixes: import the root into a truststore with `keytool -importcert` and start Java with `-Djavax.net.ssl.trustStore=... -Djavax.net.ssl.trustStorePassword=...`; or add the root to the system store (`/usr/local/share/ca-certificates/` + `update-ca-certificates`), which on Ubuntu also updates Java's `cacerts` through `ca-certificates-java`.
