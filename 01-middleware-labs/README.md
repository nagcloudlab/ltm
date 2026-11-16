# Ubuntu middleware labs — Payment Operations

- Seven incremental labs, one project, your Ubuntu laptop: install, configure, deploy, observe, break and recover middleware.
- Website files, compiled WARs, configuration stages and the Tomcat distribution are included. No application coding is required.

## Start on your Ubuntu laptop

Refresh package lists:

```bash
sudo apt update
```

Install Git:

```bash
sudo apt install -y git
```

Go to your home folder:

```bash
cd ~
```

Clone the repository:

```bash
git clone https://github.com/nagcloudlab/ltm.git ~/ltm
```

Enter the labs folder:

```bash
cd ~/ltm/middleware-labs
```

- Already cloned? Use `cd ~/ltm && git pull --ff-only` instead.
- Then follow [laptop setup](00-student-start.md) and the guides below in order.
- See also: [preparation and recovery notes](00-preparation.md), [validation record](VALIDATION.md).

| Lab | Guide | What you add |
| --- | --- | --- |
| 0 | [Linux skills](00-linux-skills.md) | Navigation, vi, permissions, processes, ports, services, logs, archives |
| 1 | [Apache](01-apache.md) | Static portal, virtual host, permissions, authentication, logs |
| 2 | [Nginx](02-nginx.md) | Same portal on a second web server, server blocks, logs |
| 3 | [Tomcat](03-tomcat.md) | Java service, WAR deployment, systemd, application errors |
| 4 | [Reverse proxies](04-reverse-proxy.md) | Apache and Nginx both forward to Tomcat |
| 5 | [API gateway](05-api-gateway.md) | Kong routes, consumers, API keys, ACLs and rate limiting |
| 6 | [Reading logs](07-reading-logs.md) | Every log in the stack, one request across hops, IST/UTC, IIS logs on Linux |
| — | [Troubleshooting drills](08-troubleshooting-drills.md) | 14 break → evidence → fix scenarios with the owning team |

- After the labs: record results in the [evidence worksheet](06-student-evidence.md), then compare with the [knowledge-check answers](09-knowledge-check-answers.md).

## The project grows in place

```text
Lab 1: curl/browser -> Apache :80 -> prepared portal files
Lab 2: curl/browser -> Nginx :8081 -> same portal files
Lab 3: curl -> Tomcat 127.0.0.1:8080 -> payment.war
Lab 4: curl -> Apache :80 OR Nginx :8081 -> Tomcat -> payment.war
Lab 5: curl -> Kong :8000 -> Tomcat -> payment.war
```

- Apache, Nginx, Tomcat and Kong run as native Ubuntu services.
- Kong Admin API and Tomcat stay on loopback.
- The two web proxies stay separate comparison paths; the gateway guide ends with a lockdown exercise.
- Classroom topology: sample data, sample secrets, no database, no real money. API keys are sent with curl; the static page embeds no secret and does not call the secured gateway.

## Repository layout

- `project-files/web/` — finished portal files
- `project-files/apps/` — ready-to-deploy good and deliberately broken WARs
- `project-files/config/` — reference configurations to copy and inspect
- `project-files/kong/` — four complete gateway stages
- `project-files/samples/` — fixed sample logs (Apache, Nginx, Tomcat, Kong, IIS) for Lab 6
- `payment-app/` — application source and reference scripts (already built; you need not run them)
- `06-student-evidence.md` — per-lab evidence worksheet and final incident

## Ground rules

- Bash on Ubuntu 24.04 LTS, as a normal sudo-capable user. Commands have no prompt symbols.
- Do not continue past a failed verification.
- Keep the same laptop across all labs.

## Update between sessions

Go to the repository:

```bash
cd ~/ltm
```

Check for local changes:

```bash
git status --short
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

- Guides reference `~/ltm/middleware-labs/project-files/`; evidence and backups go under `~/lab/`.
- Practice on installed copies under `/etc`, `/var/www` and `/opt/tomcat`. Pulling does not overwrite them or restart services.
