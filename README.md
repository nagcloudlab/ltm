# Middleware administration labs

Hands-on Ubuntu laptop labs using one incremental Payment Operations project. All application files are prepared; you focus on installing, configuring, deploying and troubleshooting middleware.

Start with [the lab index](middleware-labs/README.md) and [Ubuntu laptop setup](middleware-labs/00-student-start.md). The guides cover Linux skills, Apache, Nginx, Tomcat, reverse proxies, the Kong API gateway, reading logs and troubleshooting drills.

Clone on each Ubuntu laptop:

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/nagcloudlab/ltm.git ~/ltm
cd ~/ltm/middleware-labs
```

Already cloned? Run `cd ~/ltm && git pull --ff-only`. Prepared website files, compiled WARs, configurations and Tomcat are under `middleware-labs/project-files/`. Source and optional application maintenance scripts are under `middleware-labs/payment-app/`. You do not need to build the app.
