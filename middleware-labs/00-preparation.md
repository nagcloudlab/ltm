# Before you start

- Ubuntu Desktop 24.04 LTS laptop with sudo access, internet, 4 GB RAM and 20 GB free disk.
- All commands and browser requests run locally.

## 1. Get the project

- Follow [student setup](00-student-start.md). Already cloned? Update and verify.

Go to the repository:

```bash
cd ~/ltm
```

Pull updates:

```bash
git pull --ff-only
```

Enter the project files:

```bash
cd middleware-labs/project-files
```

Verify checksums:

```bash
sha256sum -c SHA256SUMS
```

- Supplied: website, compiled WARs, Tomcat distribution. You install Apache, Nginx, Java and native Kong during the labs.

## 2. Practice in order

[Linux skills](00-linux-skills.md) → [Apache](01-apache.md) → [Nginx](02-nginx.md) → [Tomcat](03-tomcat.md) → [Reverse proxies](04-reverse-proxy.md) → [API gateway](05-api-gateway.md) → [Reading logs](07-reading-logs.md) → [Troubleshooting drills](08-troubleshooting-drills.md)

- Check ports 80, 8081, 8080, 8000 and 8001 before starting.
- Edit installed copies of configurations; keep the Git checkout clean.
- Keep backups and evidence in `~/lab/`.
- Use two local terminals: one for commands, one for logs.
- Validate before reloading; recover each fault before continuing.
- Record results in the [evidence worksheet](06-student-evidence.md).

## 3. Finish or repeat

- Each guide includes its own recovery commands.

Stop the completed stack:

```bash
sudo systemctl stop payment-kong tomcat nginx apache2
```

- Keep installed files, backups and evidence for the next session.
- See [validation status](VALIDATION.md) for checks done on the supplied materials.
