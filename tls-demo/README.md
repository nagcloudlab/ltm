# TLS in depth — Java HTTP client and server

- One small money-transfer service (`POST /transfer`), shown three ways: plain HTTP, HTTPS, and HTTPS with client certificates (mTLS).
- Plain Java 17+ only: the JDK's built-in `HttpServer`/`HttpsServer` and `HttpClient`. No build tool, no libraries: run each file with `java File.java`.
- You create every key and certificate yourself with `openssl` and `keytool`.

## Order

| Demo | Guide | What you learn |
| --- | --- | --- |
| 1 | [HTTP, no TLS](demo-1-no-tls/README.md) | Why TLS exists: a packet capture shows the token and PIN |
| 2 | [HTTPS](demo-2-tls/README.md) | Create a root CA, intermediate CA and server certificate; keystore and truststore; chain, host-name check, handshake (TLS 1.3 vs 1.2), common errors |
| 3 | [Mutual TLS](demo-3-mtls/README.md) | Create client certificates; client authentication vs authorization; reading errors on both sides |

- Each demo has its own `README.md` with every step, including the certificate commands it needs.

## Ports

| Port | Demo |
| --- | --- |
| 9080 | Demo 1 HTTP |
| 9443 | Demo 2 HTTPS |
| 9444 | Demo 3 mTLS |

## Tools

Install the tools (Ubuntu):

```bash
sudo apt install -y openjdk-21-jdk-headless openssl curl tcpdump
```

Check Java (17 or newer):

```bash
java -version
```

- macOS works too: Java 17+, and the built-in `openssl` (LibreSSL) and `curl`; capture on `lo0` instead of `lo`.

## Layout

```text
tls-demo/
  certs/            *.ext extension files; the keys, certificates and keystores you create land here (git-ignored)
  demo-1-no-tls/    Server.java, Client.java, README
  demo-2-tls/       Server.java, Client.java, README
  demo-3-mtls/      Server.java, Client.java, README
```

- Keys, certificates and keystores are classroom-only; all passwords are `changeit`.
