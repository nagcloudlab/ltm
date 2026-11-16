# Demo 2 — HTTPS (server-side TLS)

- **Needs:** [Demo 1](../demo-1-no-tls/README.md) done; `openssl` and Java 17+ (`keytool` comes with Java)
- **You build:** your own CA and a server certificate, then the same transfer service over HTTPS: the server proves its identity with a certificate, the traffic is encrypted, and the client checks CA, chain and host name

```text
Client.java / curl  ---- TLS handshake ---->  Server.java :9443  (server.p12: key + localhost cert + intermediate)
   trusts truststore.p12 (Demo Root CA)
   checks: signature chain -> root, dates, host name in SAN
                     ==== encrypted HTTP: POST /transfer ====>
```

## What changed from demo 1

| | Demo 1 | Demo 2 |
| --- | --- | --- |
| Server class | `HttpServer` | `HttpsServer` + `SSLContext` with the server keystore |
| Client | `HttpClient.newHttpClient()` | `HttpClient` with an `SSLContext` built from the truststore |
| URL | `http://localhost:9080` | `https://localhost:9443` |
| On the wire | readable | encrypted |

- Read both `.java` files: the numbered comments mark each TLS step.

## Part A — create the CA and the server certificate

```text
Demo Root CA            (self-signed, CA:TRUE)              root.crt / root.key            -> truststore.p12 (clients trust this)
  └── Demo Intermediate CA   (CA:TRUE, pathlen:0)           intermediate.crt / .key        <- signs the day-to-day certificates
        └── localhost        (serverAuth, SAN=localhost)    server.crt / server.key        -> server.p12 (demos 2 and 3)
```

| File type | What it is | Secret? |
| --- | --- | --- |
| `.key` | Private key | **Yes**, never share or commit |
| `.csr` | Certificate signing request: public key + name, sent to a CA | No |
| `.crt` | Certificate: public key + name + CA signature (PEM text) | No |
| `.ext` | Extensions the CA writes into the certificate when signing (supplied) | No |
| `.p12` | PKCS#12 keystore for Java: key and/or certificates, password protected | Yes if it holds a key |

- All files go into the shared `~/ltm/tls-demo/certs` folder; demo 3 uses them too.
- All keystore passwords are `changeit`; `-nodes` leaves the `.key` files without a password (classroom only).
- `certs/.gitignore` keeps every generated file out of git.

## 1. Go to the certificates folder

Go to the folder:

```bash
cd ~/ltm/tls-demo/certs
```

Read the extension files used in this demo:

```bash
cat intermediate.ext server.ext
```

- `openssl x509 -req` copies only the name and public key into a certificate; `-extfile` adds the rules below at signing time. The CA decides them, not the requester.

| Extension | Meaning |
| --- | --- |
| `basicConstraints = CA:TRUE, pathlen:0` | May sign certificates, but only end certificates (no further CAs) |
| `basicConstraints = CA:FALSE` | End certificate: may not sign anything |
| `keyUsage` | What the key may do: `keyCertSign` (CA), `digitalSignature` (TLS) |
| `extendedKeyUsage = serverAuth` | May be used as a TLS server certificate |
| `subjectAltName = DNS:localhost` | The host names the certificate is valid for; clients check this, not the CN |
| `subjectKeyIdentifier`, `authorityKeyIdentifier` | IDs that link each certificate to the CA that signed it |

## 2. Create the root CA

- One command: a new 4096-bit RSA key and a self-signed certificate valid for 10 years.

Create the root key and certificate:

```bash
openssl req -x509 -newkey rsa:4096 -nodes -keyout root.key -out root.crt -days 3650 -subj "/O=LTM Training/CN=Demo Root CA" -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"
```

| Option | Meaning |
| --- | --- |
| `req -x509` | Make a certificate directly (self-signed) instead of a request |
| `-newkey rsa:4096` | Create a new RSA private key, 4096 bits |
| `-days 3650` | Valid for 10 years |
| `-subj` | The name: organisation and common name |
| `-addext` | The root's extensions, given inline: a CA that may sign certificates |

Show the root certificate:

```bash
openssl x509 -in root.crt -noout -subject -issuer -ext basicConstraints
```

- **Expected:** subject and issuer are the same (self-signed), `CA:TRUE`.

```text
subject=O = LTM Training, CN = Demo Root CA
issuer=O = LTM Training, CN = Demo Root CA
X509v3 Basic Constraints: critical
    CA:TRUE
```

- On macOS (LibreSSL) `-ext` is not available; use `openssl x509 -in root.crt -noout -text` and read the same fields.

## 3. Create the intermediate CA

- Real CAs keep the root offline and sign day-to-day certificates with an intermediate.

Create the intermediate key and signing request:

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout intermediate.key -out intermediate.csr -subj "/O=LTM Training/CN=Demo Intermediate CA"
```

Sign it with the root CA:

```bash
openssl x509 -req -in intermediate.csr -CA root.crt -CAkey root.key -CAcreateserial -days 1825 -sha256 -extfile intermediate.ext -out intermediate.crt
```

| Option | Meaning |
| --- | --- |
| `x509 -req -in …csr` | Turn a request into a certificate |
| `-CA`, `-CAkey` | The CA certificate and key that sign it |
| `-CAcreateserial` | Create `root.srl` to number the certificates this CA issues |
| `-extfile` | Add the extensions from the `.ext` file |

- **Expected:** `Certificate request self-signature ok` and `subject=O = LTM Training, CN = Demo Intermediate CA`.

## 4. Create the server certificate

Create the server key and signing request:

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/O=LTM Training/CN=localhost"
```

Check the request (signed by its own key, so the CA knows the requester holds the key):

```bash
openssl req -in server.csr -noout -subject -verify
```

- **Expected:** `Certificate request self-signature verify OK`.

Sign it with the intermediate CA:

```bash
openssl x509 -req -in server.csr -CA intermediate.crt -CAkey intermediate.key -CAcreateserial -days 365 -sha256 -extfile server.ext -out server.crt
```

Show the important fields:

```bash
openssl x509 -in server.crt -noout -subject -issuer -dates -ext subjectAltName,basicConstraints,keyUsage,extendedKeyUsage
```

- Sample output:

```text
subject=O = LTM Training, CN = localhost
issuer=O = LTM Training, CN = Demo Intermediate CA
notBefore=Nov 16 10:16:04 2026 GMT
notAfter=Nov 16 10:16:04 2027 GMT
X509v3 Basic Constraints: critical
    CA:FALSE
X509v3 Key Usage: critical
    Digital Signature, Key Encipherment
X509v3 Extended Key Usage: 
    TLS Web Server Authentication
X509v3 Subject Alternative Name: 
    DNS:localhost
```

- **Why:** the SAN lists only `localhost`, so `https://127.0.0.1:…` will fail the name check (fault B).

Prove the certificate and key belong together (both hashes must match):

```bash
openssl x509 -in server.crt -noout -modulus | openssl sha256
```

```bash
openssl rsa -in server.key -noout -modulus | openssl sha256
```

## 5. Verify the server chain

Verify with the root as trust and the intermediate as the link:

```bash
openssl verify -CAfile root.crt -untrusted intermediate.crt server.crt
```

- **Expected:** `server.crt: OK`.
- `-CAfile` = what you trust (the root); `-untrusted` = extra chain certificates to build the path.

Verify without the intermediate:

```bash
openssl verify -CAfile root.crt server.crt
```

- **Expected:** `error 20 at 0 depth lookup: unable to get local issuer certificate`: the path root → intermediate → server cannot be built.

## 6. Build the server keystore and the truststore

- Java reads PKCS#12 keystores (`.p12`). A **keystore** holds *my* key + certificate chain; a **truststore** holds the CA certificates *I trust*.

Server keystore: key + server certificate + intermediate:

```bash
openssl pkcs12 -export -name server -inkey server.key -in server.crt -certfile intermediate.crt -out server.p12 -passout pass:changeit
```

A broken server keystore without the intermediate (for fault C):

```bash
openssl pkcs12 -export -name server -inkey server.key -in server.crt -out server-no-intermediate.p12 -passout pass:changeit
```

Truststore with only the root CA certificate:

```bash
keytool -importcert -noprompt -alias demo-root-ca -file root.crt -keystore truststore.p12 -storetype PKCS12 -storepass changeit
```

- **Expected:** `Certificate was added to keystore`.

Show the chain stored with the server key:

```bash
keytool -list -v -keystore server.p12 -storepass changeit | grep -E 'Alias name|Certificate chain length|^Owner|^Issuer'
```

```text
Alias name: server
Certificate chain length: 2
Owner: CN=localhost, O=LTM Training
Issuer: CN=Demo Intermediate CA, O=LTM Training
Owner: CN=Demo Intermediate CA, O=LTM Training
Issuer: CN=Demo Root CA, O=LTM Training
```

List the truststore:

```bash
keytool -list -keystore truststore.p12 -storepass changeit
```

- **Expected:** one `demo-root-ca, …, trustedCertEntry`: a certificate only, no private key.

## Part B — run the HTTPS service

## 7. Start the HTTPS server

**Terminal A** — go to the demo folder:

```bash
cd ~/ltm/tls-demo/demo-2-tls
```

Start the server:

```bash
java Server.java
```

- **Expected:** `HTTPS server listening on https://localhost:9443/transfer with ../certs/server.p12`.

## 8. Send a transfer over TLS

**Terminal C** — go to the demo folder:

```bash
cd ~/ltm/tls-demo/demo-2-tls
```

Send one transfer:

```bash
java Client.java
```

- **Expected:**

```text
TLS      TLSv1.3  TLS_AES_256_GCM_SHA384
  server chain [0] CN=localhost,O=LTM Training  (issuer: CN=Demo Intermediate CA,O=LTM Training)
  server chain [1] CN=Demo Intermediate CA,O=LTM Training  (issuer: CN=Demo Root CA,O=LTM Training)
SENT     POST https://localhost:9443/transfer  body=from=ACC-1001&to=ACC-1002&amount=5000&pin=4321
REPLY    200 OK transfer accepted
```

| Output | Meaning |
| --- | --- |
| `TLSv1.3` | Protocol version both sides agreed on |
| `TLS_AES_256_GCM_SHA384` | Cipher suite: AES-256 in GCM mode encrypts and protects the data |
| `server chain [0]` | The server's own certificate (leaf) |
| `server chain [1]` | The intermediate; the server sends it, the client already has the root |

- Terminal A shows `TLS      TLSv1.3  TLS_AES_256_GCM_SHA384` and the received request: the server still sees everything, only the wire is protected.

The same with curl, trusting our root CA:

```bash
curl --cacert ../certs/root.crt -H 'Authorization: Bearer secret-token-123' -d 'from=ACC-1001&to=ACC-1002&amount=5000&pin=4321' https://localhost:9443/transfer
```

- **Expected:** `OK transfer accepted`.

## 9. Prove the traffic is encrypted

**Terminal B** — capture port 9443:

```bash
sudo tcpdump -i lo -A -nn 'tcp port 9443'
```

**Terminal C** — send again:

```bash
java Client.java
```

- **Expected:** terminal B shows only unreadable bytes: no `POST`, no `Authorization`, no `pin=`.
- Even the certificates are invisible: in TLS 1.3 everything after `ServerHello` is encrypted.
- Stop tcpdump with Ctrl+C.

## 10. Watch the handshake

List the handshake messages the client sends and receives:

```bash
java -Djavax.net.debug=ssl:handshake Client.java 2>&1 | grep -oE '(Produced|Consuming) [A-Za-z ]+(handshake message|message)' | uniq
```

- **Expected (TLS 1.3):**

```text
Produced ClientHello handshake message
Consuming ServerHello handshake message
Consuming ChangeCipherSpec message
Consuming EncryptedExtensions handshake message
Consuming server Certificate handshake message
Consuming CertificateVerify handshake message
Consuming server Finished handshake message
Produced client Finished handshake message
Consuming NewSessionTicket message
```

| Message | What happens |
| --- | --- |
| ClientHello | Client offers versions, cipher suites and its key share |
| ServerHello | Server picks version + cipher and sends its key share; both now derive the same secret keys |
| EncryptedExtensions | First encrypted message |
| Certificate | Server sends its chain (leaf + intermediate) |
| CertificateVerify | Server signs the handshake with its **private key**: proves it owns the certificate |
| Finished | Both sides confirm nobody changed the handshake |
| NewSessionTicket | Ticket to resume the session faster next time |

- `ChangeCipherSpec` in TLS 1.3 is only there for compatibility with old middleboxes.

Force TLS 1.2 on the client and compare:

```bash
java -Djdk.tls.client.protocols=TLSv1.2 -Djavax.net.debug=ssl:handshake Client.java 2>&1 | grep -oE '(Produced|Consuming) [A-Za-z ]+(handshake message|message)' | uniq
```

- **Expected (TLS 1.2):**

```text
Produced ClientHello handshake message
Consuming ServerHello handshake message
Consuming server Certificate handshake message
Consuming ECDH ServerKeyExchange handshake message
Consuming ServerHelloDone handshake message
Produced ECDHE ClientKeyExchange handshake message
Produced ChangeCipherSpec message
Produced client Finished handshake message
Consuming ChangeCipherSpec message
Consuming server Finished handshake message
```

- **Why:** TLS 1.2 needs two round trips and sends the certificate unencrypted; TLS 1.3 needs one and encrypts it.

Run the client with TLS 1.2 normally:

```bash
java -Djdk.tls.client.protocols=TLSv1.2 Client.java
```

- **Expected:** `TLS      TLSv1.2  TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`: the server accepts the older version; the cipher suite name now also names the key exchange (`ECDHE`) and the certificate type (`RSA`).

## 11. Inspect the server like an administrator

Connect with openssl, trusting our root:

```bash
echo | openssl s_client -connect localhost:9443 -CAfile ../certs/root.crt -brief
```

- **Expected:**

```text
CONNECTION ESTABLISHED
Protocol version: TLSv1.3
Ciphersuite: TLS_AES_256_GCM_SHA384
Peer certificate: O = LTM Training, CN = localhost
Hash used: SHA256
Signature type: RSA-PSS
Verification: OK
Server Temp Key: X25519, 253 bits
```

- A `Can't use SSL_get_servername` line before it is harmless.

Show the chain the server sends:

```bash
echo | openssl s_client -connect localhost:9443 -showcerts 2>/dev/null | grep -E '^ ?[0-9] s:|^ +i:'
```

- **Expected:** two certificates, `0` = leaf, `1` = intermediate.

```text
 0 s:O = LTM Training, CN = localhost
   i:O = LTM Training, CN = Demo Intermediate CA
 1 s:O = LTM Training, CN = Demo Intermediate CA
   i:O = LTM Training, CN = Demo Root CA
```

## 12. Fault A — the client does not trust our CA

**Break** — use Java's built-in public CA list instead of our truststore:

```bash
java Client.java https://localhost:9443/transfer java-default
```

- **Expected:**

```text
TLS FAILED  SSLHandshakeException: (certificate_unknown) PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException: unable to find valid certification path to requested target
```

The same with curl (system CA list):

```bash
curl -d 'x=1' https://localhost:9443/transfer
```

- **Expected:** `curl: (60) SSL certificate problem: unable to get local issuer certificate`.
- **Why:** our root CA is private: nobody trusts it until it is added to their truststore.
- `curl -k` would skip the check and connect; that hides exactly the attack TLS protects against: never use it in production.

**Recover** — use our truststore (the default):

```bash
java Client.java
```

## 13. Fault B — wrong host name

**Break** — connect by IP address; the certificate only lists `DNS:localhost`:

```bash
java Client.java https://127.0.0.1:9443/transfer
```

- **Expected:**

```text
TLS FAILED  SSLHandshakeException: (certificate_unknown) No subject alternative names matching IP address 127.0.0.1 found
```

The same with curl:

```bash
curl --cacert ../certs/root.crt -d 'x=1' https://127.0.0.1:9443/transfer
```

- **Expected:** `curl: (60) SSL: no alternative certificate subject name matches target host name '127.0.0.1'`.
- **Why:** a valid certificate for *another* name proves nothing about *this* server. Fix: use the name in the SAN, or issue a certificate with `IP:127.0.0.1` added to `subjectAltName`.
- Terminal A shows nothing: the client aborted the handshake, before any HTTP request existed.

## 14. Fault C — the server forgets the intermediate

**Break** — stop the server in terminal A (Ctrl+C), then start it with the keystore that has no intermediate:

```bash
java Server.java ../certs/server-no-intermediate.p12
```

**Observe** — in terminal C:

```bash
java Client.java
```

- **Expected:** `TLS FAILED  SSLHandshakeException: (certificate_unknown) PKIX path building failed: …`

Show the chain the server sends now:

```bash
echo | openssl s_client -connect localhost:9443 -showcerts 2>/dev/null | grep -E '^ ?[0-9] s:|^ +i:'
```

- **Expected:** only certificate `0`: the leaf. The client has the root, but nothing connects the leaf to the root.

```text
 0 s:O = LTM Training, CN = localhost
   i:O = LTM Training, CN = Demo Intermediate CA
```

- **Why:** one of the most common real outages after a certificate renewal: the new certificate is installed without its chain. Browsers sometimes hide it (they cache intermediates); Java and curl do not.

**Recover** — Ctrl+C in terminal A, then start with the full keystore:

```bash
java Server.java
```

**Verify:**

```bash
java Client.java
```

- **Expected:** `REPLY    200 OK transfer accepted`.

## 15. Stop

- Ctrl+C in terminal A.

## Check yourself

- Which file must never leave the machine: `server.crt`, `server.csr` or `server.key`?
- What stops the intermediate CA from creating another CA below it?
- Why does `server.p12` contain the intermediate certificate, but `truststore.p12` only the root?
- Which three checks does the client make on the server certificate?
- Which handshake message proves the server owns the private key?
- Why did connecting to `127.0.0.1` fail although it is the same server?
- After a renewal, Java clients fail with `PKIX path building failed` but your browser works. What do you check first?
- What does `curl -k` turn off, and why is it dangerous?

**Next:** [Demo 3 — mutual TLS](../demo-3-mtls/README.md).
