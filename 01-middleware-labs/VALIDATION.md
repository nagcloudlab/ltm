# Validation record

**Date:** 2026-11-15. **Platform:** Ubuntu 24.04.5 LTS (noble) with systemd as PID 1, **arm64** (`aarch64`), run as a normal sudo-capable user named `student`. The repository folder was placed at `~/ltm/middleware-labs` exactly as a student clone would have it.

**Versions observed:** Apache 2.4.58 (Ubuntu), Nginx 1.24.0 (`1.24.0-2ubuntu7.19`), OpenJDK 21.0.13 (`openjdk-21-jre-headless`), Apache Tomcat 10.1.61 (supplied tarball), Kong OSS 3.9.1 (`kong=3.9.1` from Kong's `gateway-39` apt repository for noble/arm64), curl 8.5.0.

## Executed end to end

Every command block in these guides was run in order, as written:

- [Student start](00-student-start.md): tools install, clone, `sha256sum -c SHA256SUMS` (all 21 files `OK`), port check, evidence folder.
- [Lab 1 — Apache](01-apache.md): install, deploy, virtual host, `/etc/hosts`, 200/404/403/401/200/301, log counts, fault A (403 + `AH00035`), fault B (`AH00526` while still serving 200), directory-listing 403 (`AH01276`).
- [Lab 2 — Nginx](02-nginx.md): install fails on port 80 as described (`bind() ... (98: Address already in use)`), recovery on 8081, the same eight responses, `stub_status`, missing-semicolon fault, wrong-root fault (Nginx 404, Apache 200).
- [Lab 3 — Tomcat](03-tomcat.md): checksum, install, loopback connector, systemd unit, ROOT 200, WAR deploy (`/payment/status` 200, `/balance` 42500, `/payments` 404), `/fail` 500 with stack trace, broken WAR (404 + `ClassNotFoundException: lab.PaymentServlet`, auto-undeploy), port 8090 fault and restore.
- [Lab 4 — Reverse proxies](04-reverse-proxy.md): both proxies 200, three-log trace, Tomcat stopped (Nginx 502, Apache 503, direct refused, static 200), slow backend (Nginx 504 at 10 s, direct 200 at 15 s), Apache mispointed (503 while Nginx and direct 200), 500 passed through.
- [Lab 5 — API gateway](05-api-gateway.md): Kong repository and 3.9.1 install, DB-less parse, `payment-kong` systemd service, loopback 8000/8001, routing 200/404, key-auth 401/401/200/200, rejected request absent from Tomcat log, ACL 401/403/200, 500 and 502 through Kong, rate limit `200 200 200 200 200 429 429` then 429 (`Retry-After: 60`, `X-RateLimit-Limit-Minute: 5`), invalid plugin parse failure while still serving 200, stage 4 handoff, optional lockdown (both proxy paths 404, static 200, gateway 200).
- [Evidence worksheet](06-student-evidence.md): final-incident faults 1–5 each reproduced from the Lab 4 + stage 3 starting state and recovered; afterwards Apache/Nginx static, direct Tomcat, both proxy paths and the authorized gateway all returned 200. All eight knowledge-check questions are answerable from Labs 2–5.
- [Before you start](00-preparation.md): the stop command stops all four services; starting them again restores every check.

Substitutions for non-interactive execution: `htpasswd -c -b ... admin <password>` in place of the password prompt, and `curl -u admin:<password>` in place of `curl -u admin`. `tail -f` and `journalctl -f` steps were replaced by reading the logs afterwards. The web pages were re-deployed after the portal restyle and gave the same 200/404/403/401/301 results on both servers.

## Fixed during this run

- **Tomcat would not start** (Lab 3): the tarball ships `conf/` as mode 700/600, so the `tomcat` group could not read `server.xml` (`FileNotFoundException ... (Permission denied)`, restart loop). Added `chmod -R g+rX /opt/tomcat/conf`, plus a `tomcat`-owned `conf/Catalina/localhost`, which removes a `SEVERE Unable to create directory for deployment` message.
- **Tomcat access log is buffered** (about 10 s): immediate `grep` checks in Labs 3, 4 and 5 found nothing. Added `sleep 10` before those greps and an explanatory note.
- **Port-change fault** (Lab 3): `ss` ran before Tomcat had bound 8090. Added a wait.
- **Stage 3 reload after an exhausted quota** (Lab 5 §9): the first call could still return 429 from stage 4. Added a wait and a note.
- **Kong pin**: the repository's candidate is 3.9.4; added `apt-mark hold kong` so a later `apt upgrade` keeps 3.9.1.
- Added exact expected lines where the guides were vague (Apache `AH00558`/`AH00526`/`AH00035`/`AH01276`, Nginx bind and semicolon errors, Tomcat listener shown as `[::ffff:127.0.0.1]:8080` and status line without `OK`, Kong 401/403/404/429/502 messages, parse error text, Apache `502 Proxy Error` for the slow backend).
- Added the start-state commands for the final incident, and a note for students who already cloned while following the README.

## Not verified

- **AMD64**: not run. The guides use architecture-neutral steps (the Java symlink resolves `java-21-openjdk-amd64`, and Kong publishes the same version for amd64), but no amd64 run has been made.
- **Ubuntu Desktop specifics**: no desktop session. Browser steps (`http://portal.example.test/`, `:8081`, `:8080`) were not opened in a browser; the same URLs were checked with curl. Behaviour of `ufw` on a desktop with the firewall enabled was not checked (it was inactive). `sudo -v` was not exercised with a real password prompt.
- **Clone from GitHub**: the public repository cloned successfully, but these lab files were copied in locally because they were not yet published at test time. Re-run `sha256sum -c SHA256SUMS` after publishing.
- Reboot persistence of the enabled services, and repeat runs over an existing installation, were not tested.
- Timings came from a shared, busy host; on a laptop, deploy and reload waits may be shorter or longer.

## Changed after the end-to-end run

- `project-files/config/kong.conf` now sets `admin_gui_listen = off`, so Kong 3.9.1 no longer opens Kong Manager on 0.0.0.0:8002/8445. This one-line change was not re-run end to end.
- New guides `00-linux-skills.md`, `07-reading-logs.md`, `08-troubleshooting-drills.md` and the sample logs in `project-files/samples/` were tested separately on the same Ubuntu 24.04 arm64 setup; vi, less and `tail -f` keystrokes were not exercised.

## Run on a real amd64 VM (2026-11-15)

**Platform:** Google Cloud VM, Ubuntu 24.04.5 LTS (noble), **amd64** (`x86_64`), 2 vCPU / 4 GB, kernel `7.0.0-1017-gcp`, systemd and systemd-resolved as on a laptop, run as a normal sudo-capable user (`nag`). The repository was the existing clone with these lab files copied in (uncommitted).

**Versions observed:** Apache 2.4.58 (`2.4.58-1ubuntu8.19`), Nginx 1.24.0 (`1.24.0-2ubuntu7.19`), OpenJDK 21.0.13 (`openjdk-21-jre-headless 21.0.13.0.3+1-1~24.04.1`, real path `/usr/lib/jvm/java-21-openjdk-amd64`), Tomcat 10.1.61, Kong OSS 3.9.1 from `gateway-39` for noble/amd64 (candidate 3.9.4, `apt-mark hold kong` held), curl 8.5.0.

**Executed in order:** student start, Lab 0, Labs 1–5 (including the optional lockdown), Lab 6 (reading logs, Parts A–C), all 14 troubleshooting drills (break → observe → fix → verify, then the health check after each), and the final incident setup with faults 1–5 from the evidence worksheet. All 31 files passed `sha256sum -c SHA256SUMS`.

**Matched the guides:** every status code and sample line checked, including `AH00526`/`AH00035`/`AH01276`/`AH00957`/`AH01102`, the Nginx bind and semicolon errors, `[::ffff:127.0.0.1]:8080`, the `ClassNotFoundException`, 502/503/504 per proxy, Kong 401/401/200/200 then 401/403/200, the 500 and 502 through Kong, rate limit `200 200 200 200 200 429 429` then 429 (`Retry-After`, `X-RateLimit-Limit-Minute: 5`), the parse error text, and all fixed answers in Lab 6 Parts B and C. Kong listens only on loopback: 8000, 8001 and its default status port 8007. Ports 8002 and 8445 stay closed (`admin_gui_listen = off`).

**Fixed during this run:**

- **Reloads apply in the background.** On this faster machine a request sent within about a second of `systemctl reload` reached old workers. Kong: after the stage 3 reload the blocked key still got 200 instead of 403. In the drills, the health check after the drill 11 and drill 13 fixes showed 502 and 429. Nginx: Lab 2 fault B still showed 200, and its recovery still showed 404. Added a `sleep 5` "Wait for the new workers" block after the stage 2 and stage 3 reloads (Lab 5 §5–§6) and after the drill 11 and drill 13 fixes. Added an **If it fails** note to Lab 2 fault B.
- **Drill 4** (name resolution): straight after the `/etc/hosts` edit, `systemd-resolved` still answered `127.0.0.1 localhost portal.example.test` for 1–2 s, so curl still worked. Added a note to repeat the commands. After the wait, the expected `curl: (6) Could not resolve host` appears.
- **Drill 2** sample `ss` line: Apache listens on `*:80` (IPv4 and IPv6), not `0.0.0.0:80`. Corrected.
- **Lab 0** samples: corrected the `app.conf` size (49 bytes). With the desktop umask `0002`, `namei` shows `drwxrwxr-x` for `lab` and `practice`.

**Substitutions for non-interactive execution:** `htpasswd -c -b`; `curl -u admin:<password>` (Lab 1, Lab 2, drill 3); `vi` replaced by a `sed` edit giving `port=8090`; `less` replaced by `tail`. `tail -f` and `journalctl -f` were skipped and the logs read afterwards. The `git clone` step was skipped because the clone exists; `git pull --ff-only` was replaced by `git fetch` plus a status check because the files are uncommitted. Waits that the guides describe in prose ("after deployment", "after 10 seconds", "wait about 20 seconds, then run the health check") were added as `sleep`, with one second after each reload or restart to stand in for typing time. Final-incident faults 1–5 have no command blocks, so they were scripted from Labs 2–5. The Apache slow-request claim (Lab 4 §6, `502 Proxy Error` after 10 s) was checked separately.

**VM-only observations (no guide change):** the GCP image already has git, curl, vim, unzip and netcat installed, and has no `/etc/hostname`, so `ls -lh /etc/hostname` fails in Lab 0. The hostname is a fully qualified internal name, so Apache gives no `AH00558` warning. The clock is UTC, so live logs show `+0000` where a laptop in India shows `+0530`. `ufw` is inactive. `/var/www` was left over from the earlier Apache purge. Reboot persistence was not tested.
