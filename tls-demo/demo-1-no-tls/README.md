# Demo 1 — HTTP without TLS

- **Needs:** Java 17+, `curl`, `tcpdump` (`sudo apt install -y tcpdump`)
- **You build:** a small Java HTTP server and client for money transfers, and proof that anyone on the path can read the token and PIN

```text
Client.java / curl  --- POST /transfer (plain text) --->  Server.java :9080
                     Authorization: Bearer secret-token-123
                     from=ACC-1001&to=ACC-1002&amount=5000&pin=4321
```

- `Server.java`: the JDK's built-in `HttpServer`, endpoint `POST /transfer`.
- `Client.java`: the JDK's `HttpClient`, sends one transfer with a token header and a PIN.

## 1. Start the server

**Terminal A** — go to the demo folder:

```bash
cd ~/ltm/tls-demo/demo-1-no-tls
```

Start the server:

```bash
java Server.java
```

- **Expected:** `HTTP server listening on http://localhost:9080/transfer (no TLS)`.
- `java Server.java` compiles and runs a single file; no build tool needed.

## 2. Capture the traffic

**Terminal B** — capture port 9080 on the loopback interface and print the packet contents:

```bash
sudo tcpdump -i lo -A -nn 'tcp port 9080'
```

- On macOS use `-i lo0` instead of `-i lo`.
- `-A` prints each packet's bytes as text; `-nn` shows numbers instead of names.

## 3. Send a transfer

**Terminal C** — go to the demo folder:

```bash
cd ~/ltm/tls-demo/demo-1-no-tls
```

Send one transfer with the Java client:

```bash
java Client.java
```

- **Expected:**

```text
SENT     POST http://localhost:9080/transfer  body=from=ACC-1001&to=ACC-1002&amount=5000&pin=4321
REPLY    200 OK transfer accepted
```

- Terminal A shows the same request:

```text
RECEIVED POST /transfer  Authorization=Bearer secret-token-123  body=from=ACC-1001&to=ACC-1002&amount=5000&pin=4321
```

Send the same transfer with curl:

```bash
curl -X POST -H 'Authorization: Bearer secret-token-123' -d 'from=ACC-1001&to=ACC-1002&amount=5000&pin=4321' http://localhost:9080/transfer
```

- **Expected:** `OK transfer accepted`.

## 4. Read the capture

- Look at terminal B: the whole conversation is readable.
- Sample lines from the capture:

```text
POST /transfer HTTP/1.1
Authorization: Bearer secret-token-123
from=ACC-1001&to=ACC-1002&amount=5000&pin=4321
HTTP/1.1 200 OK
OK transfer accepted
```

- **Why:** plain HTTP sends bytes exactly as written. Anyone on the path (Wi-Fi, a switch, a proxy, a compromised router) can:
  - **read** the token and PIN (no confidentiality),
  - **change** the amount or account on the way (no integrity),
  - **pretend to be the server** (no authentication).
- TLS fixes all three; demo 2 shows how.

Stop tcpdump in terminal B with Ctrl+C.

## 5. Stop the server

- Press Ctrl+C in terminal A.

## Check yourself

- Name the three things an attacker on the path can do to plain HTTP traffic.
- Is a `Bearer` token safer than a password if it travels over plain HTTP?
- Why does capturing on `lo` show this traffic, even though nothing left the laptop?

**Next:** [Demo 2 — HTTPS](../demo-2-tls/README.md).
