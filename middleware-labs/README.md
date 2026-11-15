# Ubuntu middleware labs — Payment Operations

Five incremental labs, one project, your Ubuntu laptop. Install, configure, deploy, observe, break and recover middleware. The website and Java application are prepared in advance. No application coding is required.

You run these labs on your Ubuntu laptop after cloning this repository. All website files, compiled WARs, configuration stages and the Tomcat distribution are already included.

## Start on your Ubuntu laptop

```bash
sudo apt update
sudo apt install -y git
cd ~
git clone https://github.com/nagcloudlab/ltm.git ~/ltm
cd ~/ltm/middleware-labs
```

If already cloned, use `cd ~/ltm && git pull --ff-only` instead. Follow [laptop setup](00-student-start.md), then the five guides below in order. See [preparation and recovery notes](00-preparation.md) and the [validation record](VALIDATION.md).

| Lab | Guide | What you add | Suggested time |
| --- | --- | --- | --- |
| 1 | [Apache](01-apache.md) | Static portal, virtual host, permissions, authentication, logs | 75–90 min |
| 2 | [Nginx](02-nginx.md) | Same portal on a second web server, server blocks, logs | 60–75 min |
| 3 | [Tomcat](03-tomcat.md) | Java service, WAR deployment, systemd, application errors | 75–90 min |
| 4 | [Reverse proxies](04-reverse-proxy.md) | Apache and Nginx both forward to Tomcat | 75–90 min |
| 5 | [API gateway](05-api-gateway.md) | Kong routes, consumers, API keys, ACLs and rate limiting | 75–90 min |

Allow additional setup and breaks. The complete series needs roughly 6–7.5 hours of hands-on time; split it across sessions if the Day 1 presentation is also taught in full.

## The project grows in place

```text
Lab 1: curl/browser -> Apache :80 -> prepared portal files
Lab 2: curl/browser -> Nginx :8081 -> same portal files
Lab 3: curl -> Tomcat 127.0.0.1:8080 -> payment.war
Lab 4: curl -> Apache :80 OR Nginx :8081 -> Tomcat -> payment.war
Lab 5: curl -> Kong :8000 -> Tomcat -> payment.war
```

Apache, Nginx, Tomcat and Kong run as native Ubuntu services. Kong Admin API and Tomcat stay on loopback. The two web proxies remain separate comparison paths; the gateway guide includes a final lockdown exercise.

This is a classroom topology with sample data and sample secrets. API keys are sent with curl; the static page does not embed a secret or automatically call the secured gateway. No database or real money is involved.

## Repository layout

- `project-files/web/`: finished portal files.
- `project-files/apps/`: ready-to-deploy good and deliberately broken WARs.
- `project-files/config/`: reference configurations to copy and inspect.
- `project-files/kong/`: four complete gateway stages.
- `payment-app/`: payment application source and reference scripts. The application is already built; you do not need to run these scripts.
- `06-student-evidence.md`: per-lab evidence worksheet and final incident.

All command blocks target Bash on Ubuntu 24.04 LTS. Run as a normal sudo-capable user. Commands do not include prompt symbols. Do not continue past a failed verification. Keep the same laptop across all five labs.

## Update between sessions

```bash
cd ~/ltm
git status --short
git pull --ff-only
cd middleware-labs/project-files
sha256sum -c SHA256SUMS
```

Reference paths in every guide use `~/ltm/middleware-labs/project-files/`. Store evidence and backups under `~/lab/`. Practice on installed copies under `/etc`, `/var/www`, and `/opt/tomcat`; pulling the repository does not overwrite those installed copies or restart services.
