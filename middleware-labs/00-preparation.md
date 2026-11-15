# Before you start

Use your Ubuntu Desktop 24.04 LTS laptop with sudo access, internet, 4 GB RAM and 20 GB free disk. All commands and browser requests run locally.

## 1. Get the project

Follow [student setup](00-student-start.md). Already cloned? Update and verify:

```bash
cd ~/ltm
git pull --ff-only
cd middleware-labs/project-files
sha256sum -c SHA256SUMS
```

The website, compiled WARs and Tomcat distribution are supplied. You install Apache, Nginx, Java and native Kong during the labs.

## 2. Practice in order

[Apache](01-apache.md) → [Nginx](02-nginx.md) → [Tomcat](03-tomcat.md) → [Reverse proxies](04-reverse-proxy.md) → [API gateway](05-api-gateway.md).

- Check ports 80, 8081, 8080, 8000 and 8001 before starting.
- Edit installed copies of configurations; keep the Git checkout clean.
- Keep backups and evidence in `~/lab/`.
- Use two local terminals: one for commands, one for logs.
- Validate configurations before reloading and recover each fault before continuing.

Allow about 6–7.5 hours for all labs. Use the [evidence worksheet](06-student-evidence.md) to record your results.

## 3. Finish or repeat

The individual guides include recovery commands. To stop the completed stack:

```bash
sudo systemctl stop payment-kong tomcat nginx apache2
```

Keep your installed files, backups and evidence for the next session. See [validation status](VALIDATION.md) for the checks completed on the supplied materials.
