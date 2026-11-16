# Lab 3 — Deploy the payment service in Tomcat

- **Needs:** Labs 1–2 healthy; `payment.war` and `payment-broken.war` supplied
- **You build:** Tomcat under systemd, as its own user, serving the Java app on loopback port 8080

- Apache and Nginx serve files; Tomcat runs prepared application code.
- You inspect deployment and runtime only — you do not compile or change the application.

## 1. Check the handoff and install Java

- Confirm Labs 1–2 still work and port 8080 is free before adding Tomcat.

Check the Apache portal:

```bash
curl -s http://portal.example.test/health.txt
```

Check the Nginx portal:

```bash
curl -s http://portal.example.test:8081/health.txt
```

List the supplied WAR files:

```bash
ls -lh ~/ltm/middleware-labs/project-files/apps/*.war
```

Check that port 8080 is unused:

```bash
sudo ss -lntp 'sport = :8080'
```

Install the Java runtime:

```bash
sudo apt install -y openjdk-21-jre-headless
```

Check the Java version:

```bash
java -version
```

- **Expected:** both portals answer, 8080 is unused, Java reports version 21.
- **Why a JRE:** the WAR is already compiled (Java 11+, Jakarta Servlet 6.0 / Tomcat 10.1).

## 2. Check and extract the supplied Tomcat distribution

- The repository already contains a pinned Tomcat tarball and its Apache SHA-512 file in `project-files/downloads/` — no file transfer needed.

Go to the downloads folder:

```bash
cd ~/ltm/middleware-labs/project-files/downloads
```

Verify the checksum:

```bash
sha512sum -c apache-tomcat-10.1.61.tar.gz.sha512
```

Peek inside the archive:

```bash
tar -tzf apache-tomcat-10.1.61.tar.gz | head -n 12
```

- **Expected:** `OK`. Do not continue if the checksum fails.

Create the `tomcat` service account:

```bash
sudo useradd --system --user-group --home-dir /opt/tomcat --shell /usr/sbin/nologin tomcat
```

Create the install directory:

```bash
sudo install -d -o root -g tomcat -m 750 /opt/tomcat
```

Extract Tomcat:

```bash
sudo tar -xzf apache-tomcat-10.1.61.tar.gz -C /opt/tomcat --strip-components=1
```

Make root the owner, group `tomcat`:

```bash
sudo chown -R root:tomcat /opt/tomcat
```

Remove access for other users:

```bash
sudo chmod -R o-rwx /opt/tomcat
```

Let the group read the config:

```bash
sudo chmod -R g+rX /opt/tomcat/conf
```

Create the per-host config directories:

```bash
sudo install -d -o tomcat -g tomcat -m 750 /opt/tomcat/conf/Catalina /opt/tomcat/conf/Catalina/localhost
```

Make the startup scripts executable:

```bash
sudo find /opt/tomcat/bin -type f -name '*.sh' -exec chmod 750 {} +
```

Give Tomcat write access to its runtime directories:

```bash
sudo chown -R tomcat:tomcat /opt/tomcat/logs /opt/tomcat/temp /opt/tomcat/work /opt/tomcat/webapps
```

- **If `useradd` says the user exists:** check `getent passwd tomcat` and confirm it is the training account.
- **On a rerun:** do not extract over an existing installation; inspect it and use the recovery steps first.

| Directory | Purpose | Who writes |
| --- | --- | --- |
| `bin` | Startup commands | Administrator |
| `conf` | Server configuration | Administrator |
| `webapps` | Deployed applications | Tomcat (unpacks WARs) |
| `logs` | Runtime evidence | Tomcat |
| `temp`, `work` | Runtime/generated files | Tomcat |

## 3. Bind Tomcat to loopback

- Only this laptop (browser, proxies, Kong) should reach Tomcat; other computers cannot.

Back up `server.xml`:

```bash
sudo cp /opt/tomcat/conf/server.xml ~/lab/backups/tomcat-server-original.xml
```

Add the loopback address to the HTTP Connector:

```bash
sudo sed -i 's/<Connector port="8080"/<Connector address="127.0.0.1" port="8080"/' /opt/tomcat/conf/server.xml
```

Check the change:

```bash
sudo grep -n -A3 'address="127.0.0.1"' /opt/tomcat/conf/server.xml
```

- **Expected:** the HTTP Connector has both `address="127.0.0.1"` and `port="8080"`. Leave commented examples unchanged.

## 4. Register the prepared systemd service

- The service file uses a stable Java path so it works on AMD64 and ARM64.

Show the real Java path:

```bash
readlink -f "$(command -v java)"
```

Create the stable `java-21-lab` link:

```bash
sudo ln -sfn "$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")" /usr/lib/jvm/java-21-lab
```

Test Java through the link:

```bash
/usr/lib/jvm/java-21-lab/bin/java -version
```

Read the unit file:

```bash
cat ~/ltm/middleware-labs/project-files/config/tomcat.service
```

Install it:

```bash
sudo cp ~/ltm/middleware-labs/project-files/config/tomcat.service /etc/systemd/system/tomcat.service
```

Reload systemd:

```bash
sudo systemctl daemon-reload
```

Enable and start Tomcat:

```bash
sudo systemctl enable --now tomcat
```

Check the status:

```bash
sudo systemctl status tomcat --no-pager
```

Read the console output:

```bash
sudo journalctl -u tomcat -n 30 --no-pager
```

- The unit runs `catalina.sh run` in the foreground; systemd tracks Java and puts stdout/stderr in the journal.
- This setup **does not create `catalina.out`**: use `journalctl` for console output, `/opt/tomcat/logs/` for application/access logs.
- Do not also run `startup.sh` — two start methods cause port clashes.

## 5. Prove process, port and answer

- Wait a few seconds after startup if needed.

Find the Java process:

```bash
pgrep -a java
```

Check the listener:

```bash
sudo ss -lntp 'sport = :8080'
```

Request the ROOT page:

```bash
curl -I http://127.0.0.1:8080/
```

- **Expected:** a Java process; a loopback listener on 8080 (may show as `[::ffff:127.0.0.1]:8080`); `HTTP/1.1 200`.
- Tomcat omits the reason phrase, so there is no `OK` after `200`.
- Open `http://localhost:8080/` in your laptop browser to see the Tomcat page.

**If it fails** — read the journal:

```bash
sudo journalctl -u tomcat -n 60 --no-pager
```

Check that the `tomcat` user can read the config:

```bash
sudo -u tomcat test -r /opt/tomcat/conf/server.xml; echo "config read exit=$?"
```

## 6. Inspect and deploy the developer's WAR

List the WAR contents:

```bash
unzip -l ~/ltm/middleware-labs/project-files/apps/payment.war
```

Read its deployment descriptor:

```bash
unzip -p ~/ltm/middleware-labs/project-files/apps/payment.war WEB-INF/web.xml
```

Deploy the WAR:

```bash
sudo install -o tomcat -g tomcat -m 640 ~/ltm/middleware-labs/project-files/apps/payment.war /opt/tomcat/webapps/payment.war
```

Read the deployment messages:

```bash
sudo journalctl -u tomcat -n 30 --no-pager
```

List `webapps`:

```bash
sudo ls -l /opt/tomcat/webapps/
```

- Automatic deployment takes about 10 seconds.

Optional — follow the journal live in a second terminal (Ctrl+C after the deployment message):

```bash
sudo journalctl -u tomcat -f
```

Call the status page:

```bash
curl -i http://127.0.0.1:8080/payment/status
```

Call the balance page:

```bash
curl -i http://127.0.0.1:8080/payment/balance
```

Call a wrong context:

```bash
curl -I http://127.0.0.1:8080/payments/status
```

- **Expected:** `200` with `Payment Service OK`; `200` with demo JSON balance `42500`; `404`.
- **Why:** the file name `payment.war` sets the context `/payment`; `/payments` is a different context.

## 7. Find request evidence

List Tomcat's logs:

```bash
sudo ls -lh /opt/tomcat/logs/
```

Read the access log:

```bash
sudo sh -c 'tail -n 10 /opt/tomcat/logs/localhost_access_log.*.txt'
```

Read recent console output:

```bash
sudo journalctl -u tomcat --since '10 minutes ago' --no-pager
```

- The access log records paths and statuses. It is written about every 10 seconds — wait 10 s and look again before deciding a request is missing.
- Startup messages are in the journal; application exceptions can be in `localhost.YYYY-MM-DD.log`.
- Use `sudo` — the logs belong to the service account.

## 8. Fault exercise A — application 500

**Break** — call the deliberate failure:

```bash
curl -i http://127.0.0.1:8080/payment/fail
```

**Observe** — the rest of the app still works:

```bash
curl -i http://127.0.0.1:8080/payment/status
```

Read the journal:

```bash
sudo journalctl -u tomcat --since '5 minutes ago' --no-pager | tail -n 50
```

Find the stack trace:

```bash
sudo sh -c 'grep -A8 "LAB simulated payment failure" /opt/tomcat/logs/localhost.*.log'
```

Wait for the access log to flush:

```bash
sleep 10
```

Find the 500 in the access log:

```bash
sudo sh -c 'grep " 500 " /opt/tomcat/logs/localhost_access_log.*.txt'
```

- **Expected:** `/fail` returns 500; `/status` still returns 200. The stack trace is in `localhost.YYYY-MM-DD.log`, not the journal.
- Sample line:

```text
jakarta.servlet.ServletException: LAB simulated payment failure; hand stack trace to developers
```

- Capture the request and stack trace for developers. A 500 elsewhere can also come from server configuration — always check the evidence.
- **Recover:** call `/status`; the fault only happens at `/fail`. No restart needed.

## 9. Fault exercise B — an incomplete deployment

- The broken WAR has a valid descriptor but no servlet class. Deploy it as a **separate context** so the good app stays up.

**Break** — deploy the broken WAR:

```bash
sudo install -o tomcat -g tomcat -m 640 ~/ltm/middleware-labs/project-files/apps/payment-broken.war /opt/tomcat/webapps/payment-broken.war
```

**Observe** (after deployment) — call the broken context:

```bash
curl -i http://127.0.0.1:8080/payment-broken/status
```

Read the journal:

```bash
sudo journalctl -u tomcat --since '5 minutes ago' --no-pager | tail -n 60
```

Find the missing class:

```bash
sudo sh -c 'grep -A8 "ClassNotFoundException" /opt/tomcat/logs/localhost.*.log'
```

List the broken WAR's contents:

```bash
unzip -l ~/ltm/middleware-labs/project-files/apps/payment-broken.war
```

Check the good context:

```bash
curl -i http://127.0.0.1:8080/payment/status
```

- **Expected:**
  - Broken context fails to start and normally answers 404.
  - Journal: `Context [/payment-broken] startup failed due to previous errors`
  - `localhost.YYYY-MM-DD.log`: `java.lang.ClassNotFoundException: lab.PaymentServlet`
  - Good context still answers 200.
- **Why:** a missing class does not always give 500 — a startup failure can make the whole context unavailable.

**Recover** — remove only the broken WAR:

```bash
sudo rm -f /opt/tomcat/webapps/payment-broken.war
```

**Verify** (after 10 seconds) — the expanded folder is gone:

```bash
sudo ls /opt/tomcat/webapps/
```

Check the good context:

```bash
curl -I http://127.0.0.1:8080/payment/status
```

- **If `payment-broken/` remains:** stop Tomcat, remove only `/opt/tomcat/webapps/payment-broken`, start Tomcat.

## 10. Fault exercise C — Tomcat is running on the wrong port

**Break** — back up `server.xml`:

```bash
sudo cp /opt/tomcat/conf/server.xml ~/lab/backups/tomcat-server-lab3.xml
```

Change the port to 8090:

```bash
sudo sed -i 's/port="8080"/port="8090"/' /opt/tomcat/conf/server.xml
```

Restart Tomcat:

```bash
sudo systemctl restart tomcat
```

Wait for startup:

```bash
sleep 10
```

**Observe** — check the service:

```bash
systemctl is-active tomcat
```

Check the new port:

```bash
sudo ss -lntp 'sport = :8090'
```

Try the old port:

```bash
curl --max-time 3 -I http://127.0.0.1:8080/payment/status
```

Try the new port:

```bash
curl -I http://127.0.0.1:8090/payment/status
```

- **Expected:** service `active`; old port refused (`curl: (7) Failed to connect`); new port works.
- If 8090 also refuses, Tomcat is still starting — wait and repeat the last two commands.
- **Why:** a running process alone does not prove the service is reachable where clients expect it.

**Recover** — restore the backup:

```bash
sudo cp ~/lab/backups/tomcat-server-lab3.xml /opt/tomcat/conf/server.xml
```

Restart Tomcat:

```bash
sudo systemctl restart tomcat
```

## 11. Handoff and practice challenge

- Run after startup finishes.

Check all three services:

```bash
systemctl is-active apache2 nginx tomcat
```

Check the Apache portal:

```bash
curl -s http://portal.example.test/health.txt
```

Check the Nginx portal:

```bash
curl -s http://portal.example.test:8081/health.txt
```

Check the payment app:

```bash
curl -s http://127.0.0.1:8080/payment/status
```

Save startup evidence:

```bash
sudo journalctl -u tomcat -n 20 --no-pager | tee ~/lab/evidence/lab3-startup.txt
```

- **Challenge:** explain who owns what:
  - Middleware admin: `server.xml`, systemd unit, JVM settings.
  - Developers: `WEB-INF/web.xml`, servlet class, WAR build.
- Continue to [Lab 4](04-reverse-proxy.md).
- Reference: [Tomcat 10.1 setup](https://tomcat.apache.org/tomcat-10.1-doc/setup.html).
