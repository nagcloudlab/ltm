# Demo 3 — mutual TLS (mTLS)

- **Needs:** [Demo 2](../demo-2-tls/README.md) done
- **You build:** client certificates from your CA, then an HTTPS service that also demands a **client** certificate, plus an allow list: only `transfer-client` may make transfers

```text
Client.java / curl                                   Server.java :9444
  client.p12  (key + transfer-client cert + intermediate)   server.p12   (as in demo 2)
  truststore.p12 -> checks the server                       truststore.p12 -> checks the CLIENT
                     <==== both sides prove who they are ====>
  Authentication: TLS checks the client certificate chains to Demo Root CA
  Authorization:  Server.java checks the client's CN is on the allow list
```

## What changed from demo 2

| | Demo 2 | Demo 3 |
| --- | --- | --- |
| Server `SSLContext` | key managers only | key managers **+ trust managers** (which CAs may issue client certificates) |
| Server setting | — | `setNeedClientAuth(true)` |
| Client `SSLContext` | trust managers only | trust managers **+ key managers** (`client.p12`) |
| Server code | — | reads the client's CN, checks the allow list, 403 if not allowed |

- Typical use: service-to-service calls inside a company, payment networks, API gateways talking to back ends.

## Part A — create the client certificates

```text
Demo Root CA                                  (from demo 2)
  └── Demo Intermediate CA                    (from demo 2)
        ├── transfer-client  (clientAuth)     client.crt / client.key        -> client.p12   (allowed)
        └── intruder-client  (clientAuth)     intruder.crt / intruder.key    -> intruder.p12 (valid, but not allowed)

transfer-client, O=Rogue  (self-signed, NOT from our CA)   rogue.crt / rogue.key  -> rogue.p12 (untrusted)
```

- The server keeps `server.p12` from demo 2, and uses `truststore.p12` (the root) to check clients.

## 1. Go to the certificates folder

Go to the folder:

```bash
cd ~/ltm/tls-demo/certs
```

Read the client extension file:

```bash
cat client.ext
```

- `extendedKeyUsage = clientAuth`: the certificate may be used as a TLS **client** certificate; `CA:FALSE`: it may not sign anything.

## 2. Create the client certificates

The allowed client, key and request:

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout client.key -out client.csr -subj "/O=LTM Training/CN=transfer-client"
```

Sign it with the intermediate CA:

```bash
openssl x509 -req -in client.csr -CA intermediate.crt -CAkey intermediate.key -CAcreateserial -days 365 -sha256 -extfile client.ext -out client.crt
```

A second client from the same CA, which the server will not allow:

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout intruder.key -out intruder.csr -subj "/O=LTM Training/CN=intruder-client"
```

Sign it:

```bash
openssl x509 -req -in intruder.csr -CA intermediate.crt -CAkey intermediate.key -CAcreateserial -days 365 -sha256 -extfile client.ext -out intruder.crt
```

A rogue client: same name `transfer-client`, but self-signed, not from our CA:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -keyout rogue.key -out rogue.crt -days 365 -subj "/O=Rogue/CN=transfer-client"
```

Show the client certificate's name, issuer and purpose:

```bash
openssl x509 -in client.crt -noout -subject -issuer -ext extendedKeyUsage
```

- **Expected:**

```text
subject=O = LTM Training, CN = transfer-client
issuer=O = LTM Training, CN = Demo Intermediate CA
X509v3 Extended Key Usage: 
    TLS Web Client Authentication
```

## 3. Verify the client chains

Verify the two certificates from our CA:

```bash
openssl verify -CAfile root.crt -untrusted intermediate.crt client.crt intruder.crt
```

- **Expected:** `client.crt: OK` and `intruder.crt: OK`.

Verify the rogue certificate:

```bash
openssl verify -CAfile root.crt -untrusted intermediate.crt rogue.crt
```

- **Expected:** `error 18 at 0 depth lookup: self-signed certificate`: same name, but no path to our root.

## 4. Build the client keystores

Client keystore: key + client certificate + intermediate:

```bash
openssl pkcs12 -export -name client -inkey client.key -in client.crt -certfile intermediate.crt -out client.p12 -passout pass:changeit
```

Intruder keystore:

```bash
openssl pkcs12 -export -name intruder -inkey intruder.key -in intruder.crt -certfile intermediate.crt -out intruder.p12 -passout pass:changeit
```

Rogue keystore:

```bash
openssl pkcs12 -export -name rogue -inkey rogue.key -in rogue.crt -out rogue.p12 -passout pass:changeit
```

Client chain file for curl (client certificate + intermediate):

```bash
cat client.crt intermediate.crt > client-chain.crt
```

List the client keystore:

```bash
keytool -list -keystore client.p12 -storepass changeit
```

- **Expected:** one `client, …, PrivateKeyEntry`.

## Part B — run the mTLS service

## 5. Start the mTLS server

**Terminal A** — go to the demo folder:

```bash
cd ~/ltm/tls-demo/demo-3-mtls
```

Start the server and also show TLS errors (Java's handshake log, filtered to the useful lines):

```bash
java -Djavax.net.debug=ssl:handshake Server.java 2>&1 | grep --line-buffered -E 'listening|^TLS|RECEIVED|REJECTED|Fatal'
```

- **Expected:** `mTLS server listening on https://localhost:9444/transfer (client certificate required)`.

## 6. Allowed client with a valid certificate

**Terminal C** — go to the demo folder:

```bash
cd ~/ltm/tls-demo/demo-3-mtls
```

Send a transfer with `client.p12`:

```bash
java Client.java
```

- **Expected:**

```text
TLS      TLSv1.3  client certificate sent: true
SENT     POST https://localhost:9444/transfer  body=from=ACC-1001&to=ACC-1002&amount=5000&pin=4321
REPLY    200 OK transfer accepted for transfer-client
```

- Terminal A:

```text
TLS      TLSv1.3  client certificate CN=transfer-client  (issuer: CN=Demo Intermediate CA,O=LTM Training)
RECEIVED POST /transfer  body=from=ACC-1001&to=ACC-1002&amount=5000&pin=4321
```

The same with curl (certificate + intermediate in one file, and the key):

```bash
curl --cacert ../certs/root.crt --cert ../certs/client-chain.crt --key ../certs/client.key -d 'from=ACC-1001&to=ACC-1002&amount=5000&pin=4321' https://localhost:9444/transfer
```

- **Expected:** `OK transfer accepted for transfer-client`.

## 7. Watch the extra handshake messages

List the handshake messages:

```bash
java -Djavax.net.debug=ssl:handshake Client.java 2>&1 | grep -oE '(Produced|Consuming) [A-Za-z ]+(handshake message|message)' | uniq
```

- **Expected:**

```text
Produced ClientHello handshake message
Consuming ServerHello handshake message
Consuming ChangeCipherSpec message
Consuming EncryptedExtensions handshake message
Consuming CertificateRequest handshake message
Consuming server Certificate handshake message
Consuming CertificateVerify handshake message
Consuming server Finished handshake message
Produced client Certificate message
Produced client CertificateVerify handshake message
Produced client Finished handshake message
Consuming NewSessionTicket message
```

- New compared with demo 2:
  - **CertificateRequest**: the server asks for a client certificate and names the CAs it accepts.
  - **client Certificate**: the client sends its chain.
  - **client CertificateVerify**: the client signs the handshake with its private key: a stolen `client.crt` alone is useless.

See which CAs the server accepts:

```bash
echo | openssl s_client -connect localhost:9444 -CAfile ../certs/root.crt 2>/dev/null | grep -A1 'Acceptable client certificate CA names'
```

- **Expected:**

```text
Acceptable client certificate CA names
O = LTM Training, CN = Demo Root CA
```

## 8. Fault A — no client certificate

**Break** — connect without a client certificate:

```bash
java Client.java none
```

- **Expected (client):**

```text
TLS FAILED  IOException: HTTP/1.1 header parser received no bytes
```

- **Expected (terminal A):** `Fatal (CERTIFICATE_REQUIRED): Empty client certificate chain`.

The same with curl:

```bash
curl --cacert ../certs/root.crt -d 'x=1' https://localhost:9444/transfer
```

- **Expected:** `curl: (56) Recv failure: Connection reset by peer`.
- **Why the client error is vague:** in TLS 1.3 the client finishes its part of the handshake first; the server checks the client certificate afterwards and simply closes the connection. **The real reason is in the server log**: always check both sides.

## 9. Fault B — certificate from an unknown CA

**Break** — curl with the rogue certificate (`CN=transfer-client`, but self-signed):

```bash
curl --cacert ../certs/root.crt --cert ../certs/rogue.crt --key ../certs/rogue.key -d 'x=1' https://localhost:9444/transfer
```

- **Expected (client):** `curl: (56) Recv failure: Connection reset by peer`.
- **Expected (terminal A):** `Fatal (CERTIFICATE_UNKNOWN): PKIX path building failed: … unable to find valid certification path to requested target`.
- **Why:** the name is right, but no chain leads to `Demo Root CA`; anyone can type any name into a self-signed certificate.

Try the rogue keystore with the Java client:

```bash
java Client.java ../certs/rogue.p12
```

- **Expected:** the same failure as "no certificate", and terminal A shows `Empty client certificate chain`.
- **Why:** Java only offers a certificate issued by one of the CAs the server named in `CertificateRequest`; the rogue one does not match, so Java sends none. curl sends whatever you give it.

## 10. Fault C — the client forgets the intermediate

**Break** — curl with only the client certificate, no intermediate:

```bash
curl --cacert ../certs/root.crt --cert ../certs/client.crt --key ../certs/client.key -d 'x=1' https://localhost:9444/transfer
```

- **Expected (client):** `curl: (56) Recv failure: Connection reset by peer`.
- **Expected (terminal A):** `Fatal (CERTIFICATE_UNKNOWN): PKIX path building failed: …`
- **Why:** the same chain rule as demo 2 fault C, in the other direction: the server only trusts the root, so the client must send the intermediate. `client-chain.crt` and `client.p12` include it.

## 11. Fault D — valid certificate, not allowed

**Break** — use the intruder certificate (same CA, `CN=intruder-client`):

```bash
java Client.java ../certs/intruder.p12
```

- **Expected (client):**

```text
TLS      TLSv1.3  client certificate sent: true
SENT     POST https://localhost:9444/transfer  body=from=ACC-1001&to=ACC-1002&amount=5000&pin=4321
REPLY    403 FORBIDDEN intruder-client may not make transfers
```

- **Expected (terminal A):**

```text
TLS      TLSv1.3  client certificate CN=intruder-client  (issuer: CN=Demo Intermediate CA,O=LTM Training)
REJECTED intruder-client is not on the allow list
```

- **Why:** TLS answered "**who** are you?" (authentication: succeeded). The application answered "**may** you do this?" (authorization: denied). mTLS alone lets in every certificate the CA ever issued; you still need an allow list or roles.

## 12. Stop

- Ctrl+C in terminal A.

## Summary of the three demos

| | Demo 1 HTTP | Demo 2 HTTPS | Demo 3 mTLS |
| --- | --- | --- | --- |
| Data encrypted on the wire | No | Yes | Yes |
| Data protected against changes | No | Yes | Yes |
| Client knows who the server is | No | Yes (certificate) | Yes (certificate) |
| Server knows who the client is | No (only a token in the request) | No (only a token in the request) | Yes (certificate) |
| Port | 9080 | 9443 | 9444 |

| Error | Seen at | Typical cause |
| --- | --- | --- |
| `PKIX path building failed` | the side checking a certificate | CA not in truststore, or chain missing the intermediate |
| `No subject alternative names matching …` | client | host name not in the certificate's SAN |
| `curl: (60) … unable to get local issuer certificate` | curl | same as PKIX: unknown CA or missing intermediate |
| `CERTIFICATE_REQUIRED: Empty client certificate chain` | server | client sent no certificate (or none from an accepted CA) |
| `Connection reset by peer` / `header parser received no bytes` | client | server rejected the client certificate: read the server log |
| HTTP `403` after a good handshake | client | authenticated but not authorized |

## Check yourself

- The rogue certificate says `CN=transfer-client`. Why is that not enough to be trusted?
- What does the server need in demo 3 that it did not need in demo 2? And the client?
- Which handshake message stops someone who copied `client.crt` (but not `client.key`) from connecting?
- Why did the Java client send no certificate when given `rogue.p12`?
- The client only sees "connection reset". Where do you look for the real reason?
- `intruder-client` has a valid certificate from our CA. Why is it still refused, and at which layer?
- In demos 1 and 2 the server identifies the client by a bearer token. What is the advantage of a client certificate?
