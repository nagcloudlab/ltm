# Lab 3 — deploy the prepared payment service in Tomcat

**Time:** 75–90 minutes. **Prerequisite:** Labs 1–2 healthy, `payment.war` and `payment-broken.war` supplied. **Deliverable:** Tomcat runs under systemd as its own user and serves the Java application on loopback port 8080.

Apache and Nginx currently serve files. Tomcat now runs prepared application code. You inspect the deployment and runtime; they do not compile or change the application.

## 1. Check the handoff and install Java

```bash
curl -s http://portal.example.test/health.txt
curl -s http://portal.example.test:8081/health.txt
ls -lh ~/ltm/middleware-labs/project-files/apps/*.war
sudo ss -lntp 'sport = :8080'
sudo apt install -y openjdk-21-jre-headless
java -version
```

Expected: both portals work, 8080 is unused and Java reports version 21. Use a JRE: the WAR is already compiled for Java 11 or later and Jakarta Servlet 6.0/Tomcat 10.1.

## 2. Check and extract the supplied Tomcat distribution

The cloned repository includes a pinned Tomcat tarball and its Apache SHA-512 file in `project-files/downloads/`. No separate file transfer is required.

```bash
cd ~/ltm/middleware-labs/project-files/downloads
sha512sum -c apache-tomcat-10.1.61.tar.gz.sha512
tar -tzf apache-tomcat-10.1.61.tar.gz | head -n 12
```

Expected: `OK`. Do not continue if the checksum fails.

Create a dedicated service account, then extract the software:

```bash
sudo useradd --system --user-group --home-dir /opt/tomcat --shell /usr/sbin/nologin tomcat
sudo install -d -o root -g tomcat -m 750 /opt/tomcat
sudo tar -xzf apache-tomcat-10.1.61.tar.gz -C /opt/tomcat --strip-components=1
sudo chown -R root:tomcat /opt/tomcat
sudo chmod -R o-rwx /opt/tomcat
sudo chmod -R g+rX /opt/tomcat/conf
sudo install -d -o tomcat -g tomcat -m 750 /opt/tomcat/conf/Catalina /opt/tomcat/conf/Catalina/localhost
sudo find /opt/tomcat/bin -type f -name '*.sh' -exec chmod 750 {} +
sudo chown -R tomcat:tomcat /opt/tomcat/logs /opt/tomcat/temp /opt/tomcat/work /opt/tomcat/webapps
```

If `useradd` says the user already exists, inspect `getent passwd tomcat` and confirm it is the training account before continuing. Do not extract over an existing installation during a rerun; inspect the existing installation before continuing and use the recovery steps before repeating installation.

| Directory | Purpose | Who needs write access |
| --- | --- | --- |
| `bin` | Startup commands | Administrator |
| `conf` | Server configuration | Administrator |
| `webapps` | Deployed applications | Tomcat, to unpack WARs |
| `logs` | Runtime evidence | Tomcat |
| `temp`, `work` | Runtime/generated files | Tomcat |

## 3. Bind Tomcat to loopback

```bash
sudo cp /opt/tomcat/conf/server.xml ~/lab/backups/tomcat-server-original.xml
sudo sed -i 's/<Connector port="8080"/<Connector address="127.0.0.1" port="8080"/' /opt/tomcat/conf/server.xml
sudo grep -n -A3 'address="127.0.0.1"' /opt/tomcat/conf/server.xml
```

Expected: the HTTP Connector contains both `address="127.0.0.1"` and `port="8080"`. Leave commented examples unchanged. Your browser, proxies and Kong run on this same laptop and can reach loopback; other computers cannot connect to this listener.

## 4. Register the prepared systemd service

The service file uses a stable local Java path so it works on both AMD64 and ARM64 Ubuntu:

```bash
readlink -f "$(command -v java)"
sudo ln -sfn "$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")" /usr/lib/jvm/java-21-lab
/usr/lib/jvm/java-21-lab/bin/java -version
cat ~/ltm/middleware-labs/project-files/config/tomcat.service
sudo cp ~/ltm/middleware-labs/project-files/config/tomcat.service /etc/systemd/system/tomcat.service
sudo systemctl daemon-reload
sudo systemctl enable --now tomcat
sudo systemctl status tomcat --no-pager
sudo journalctl -u tomcat -n 30 --no-pager
```

The unit runs `catalina.sh run` in the foreground. systemd tracks the Java process and captures stdout/stderr in the journal. This setup **does not create `catalina.out`**; use `journalctl` for console output and Tomcat's `logs/` files for application/access logs. Do not also start `startup.sh`; two independent start methods can create port clashes.

## 5. Prove process, port and answer

```bash
pgrep -a java
sudo ss -lntp 'sport = :8080'
curl -I http://127.0.0.1:8080/
```

Wait a few seconds after startup if necessary. Expected: Java process, `127.0.0.1:8080` listener and `200` for Tomcat's supplied ROOT page. If it fails:

```bash
sudo journalctl -u tomcat -n 60 --no-pager
sudo -u tomcat test -r /opt/tomcat/conf/server.xml; echo "config read exit=$?"
```

Open `http://localhost:8080/` in your laptop browser to see the Tomcat page. Loopback binding permits local access while preventing direct connections from other computers.

## 6. Inspect and deploy the developer's WAR

```bash
unzip -l ~/ltm/middleware-labs/project-files/apps/payment.war
unzip -p ~/ltm/middleware-labs/project-files/apps/payment.war WEB-INF/web.xml
sudo install -o tomcat -g tomcat -m 640 ~/ltm/middleware-labs/project-files/apps/payment.war /opt/tomcat/webapps/payment.war
sudo journalctl -u tomcat -n 30 --no-pager
sudo ls -l /opt/tomcat/webapps/
```

Allow roughly 10 seconds for automatic deployment. In a second terminal you can follow it live:

```bash
sudo journalctl -u tomcat -f
```

Stop following with Ctrl+C after the deployment message. Verify the application:

```bash
curl -i http://127.0.0.1:8080/payment/status
curl -i http://127.0.0.1:8080/payment/balance
curl -I http://127.0.0.1:8080/payments/status
```

Expected: `200` with `Payment Service OK`, `200` with demo JSON balance `42500`, then `404`. The WAR's name `payment.war` establishes `/payment`; `/payments` is a different context.

## 7. Find request evidence

```bash
sudo ls -lh /opt/tomcat/logs/
sudo sh -c 'tail -n 10 /opt/tomcat/logs/localhost_access_log.*.txt'
sudo journalctl -u tomcat --since '10 minutes ago' --no-pager
```

The access log records request paths and statuses. Console startup messages appear in the journal; application exceptions can also appear in `localhost.YYYY-MM-DD.log`. Use `sudo` to read logs owned by the service account.

## 8. Fault exercise A — application 500

```bash
curl -i http://127.0.0.1:8080/payment/fail
curl -i http://127.0.0.1:8080/payment/status
sudo journalctl -u tomcat --since '5 minutes ago' --no-pager | tail -n 50
sudo sh -c 'grep -A8 "LAB simulated payment failure" /opt/tomcat/logs/localhost.*.log'
sudo sh -c 'grep " 500 " /opt/tomcat/logs/localhost_access_log.*.txt'
```

Expected: `/fail` intentionally returns 500; `/status` still returns 200. Capture the request and stack trace. This fixture demonstrates a developer-owned exception; a 500 in another system can also come from server configuration, so always inspect the evidence.

Recovery: call `/status`; the deliberate fault only occurs at `/fail`. No server restart is required.

## 9. Fault exercise B — an incomplete deployment

The supplied broken WAR has a valid deployment descriptor but is missing the servlet class. Deploy it as a **separate context**, leaving the good application available:

```bash
sudo install -o tomcat -g tomcat -m 640 ~/ltm/middleware-labs/project-files/apps/payment-broken.war /opt/tomcat/webapps/payment-broken.war
```

Wait for deployment, then inspect:

```bash
curl -i http://127.0.0.1:8080/payment-broken/status
sudo journalctl -u tomcat --since '5 minutes ago' --no-pager | tail -n 60
sudo sh -c 'grep -A8 "ClassNotFoundException" /opt/tomcat/logs/localhost.*.log'
unzip -l ~/ltm/middleware-labs/project-files/apps/payment-broken.war
curl -i http://127.0.0.1:8080/payment/status
```

Expected: broken context fails to start and normally answers 404; logs identify missing `lab.PaymentServlet`. The good context still answers 200. Do not assume every missing-class problem returns 500: startup failures may leave the whole context unavailable.

Remove just the deliberate broken deployment:

```bash
sudo rm -f /opt/tomcat/webapps/payment-broken.war
```

Wait 10 seconds, then confirm Tomcat undeploys its expanded folder:

```bash
sudo ls /opt/tomcat/webapps/
curl -I http://127.0.0.1:8080/payment/status
```

If the expanded `payment-broken` directory remains after auto-undeploy, stop Tomcat, remove only `/opt/tomcat/webapps/payment-broken`, then start it again.

## 10. Fault exercise C — Tomcat is running on the wrong port

```bash
sudo cp /opt/tomcat/conf/server.xml ~/lab/backups/tomcat-server-lab3.xml
sudo sed -i 's/port="8080"/port="8090"/' /opt/tomcat/conf/server.xml
sudo systemctl restart tomcat
systemctl is-active tomcat
sudo ss -lntp 'sport = :8090'
curl --max-time 3 -I http://127.0.0.1:8080/payment/status
curl -I http://127.0.0.1:8090/payment/status
```

Expected: service is active, old port refuses connection, new port works. A running process alone is insufficient. Restore:

```bash
sudo cp ~/lab/backups/tomcat-server-lab3.xml /opt/tomcat/conf/server.xml
sudo systemctl restart tomcat
```

## 11. Handoff and practice challenge

After startup finishes:

```bash
systemctl is-active apache2 nginx tomcat
curl -s http://portal.example.test/health.txt
curl -s http://portal.example.test:8081/health.txt
curl -s http://127.0.0.1:8080/payment/status
sudo journalctl -u tomcat -n 20 --no-pager | tee ~/lab/evidence/lab3-startup.txt
```

Explain which belongs to the middleware admin (`server.xml`, systemd unit, JVM settings) and which comes from developers (`WEB-INF/web.xml`, servlet class, WAR build). Continue to [Lab 4](04-reverse-proxy.md).

Reference: [Tomcat 10.1 setup](https://tomcat.apache.org/tomcat-10.1-doc/setup.html).
