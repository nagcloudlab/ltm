# 16 · Capstone incident drill: "Payment is down"

**Time:** 45 min · **Needs:** a fresh `bash ~/01-linux/setup-lab.sh` · **Work:** alone or in pairs
**Rules:** use only commands from Topics 01–11 (12–14 optional). This drill uses everything from Topics 01–11 in one story. Keep evidence. At the end, hand in `~/incident/report.txt`.

> **09:20, Monday.** PagerDuty: *"PayBank /payment 5xx rate 47%"*.
> Your manager: *"Customers can't transfer money. Find out why, fix what is ours, escalate what isn't, and send me a report by 10:00."*

```bash
bash ~/01-linux/setup-lab.sh > /dev/null
cd ~/lab/srv
mkdir -p ~/incident && : > ~/incident/report.txt
nohup scripts/rebuild_index.sh > /dev/null 2>&1 &       # the trainer's extra surprise
```

Fill in each **Finding** in your report as you go:

```bash
echo "STEP 1 finding: …" >> ~/incident/report.txt
```

---

## Step 1 · How bad, since when? (access log)

Find: total requests, how many 5xx, which URL fails most, the time of the first 5xx and of the first 503.

<details><summary>Hint</summary>

`cut -d' ' -f9 … | sort | uniq -c`, `awk '$9>=500'`, `awk '$9==503 {print $4; exit}'`
</details>

## Step 2 · What does the web server say? (Apache error log)

Why did Apache return 503 from 09:13:15? What exact address could it not reach?

## Step 3 · What does the app say? (app log)

Find the FATAL lines, read 3 lines **before** the first one, and write the timeline in 3 lines.

## Step 4 · Why did it run out? (config)

Compare production with staging. Which two settings explain the FATAL lines?

## Step 5 · Why didn't it restart? (lock file)

Find the lock file, show its content and age. Is the PID inside it still running?

## Step 6 · Why is the server slow? (CPU)

Find the process using the most CPU. Save the evidence, then stop it the right way.

## Step 7 · Is the disk OK? (space)

Find the biggest files under `~/lab/srv`. Compress yesterday's log, move the heap dump to `~/for-developers/`. Record space before and after.

## Step 8 · Did someone change something? (drift)

Compare the Apache site file with its backup. What changed, and which errors would that cause?

## Step 9 · Fix what is ours

1. Remove the stale lock file (only after Step 5 proves its PID is dead).
2. Restore the Apache site file from backup.
3. Write down (do **not** apply) the config change you recommend for `db.pool.maxTotal` and `jvm.heap.max`, and why it needs a change ticket.

## Step 10 · Escalate what isn't ours, then report

Two findings belong to other teams. Which, and to whom?

Finish `~/incident/report.txt` with: **Summary · Timeline · Root cause · Actions taken · Recommendations · Escalations**.

---

## Trainer answer key

**Step 1**

```bash
A=var/log/apache2/access.log
wc -l < $A                                             # 30
awk '$9 >= 500' $A | wc -l                              # 14
awk '$9>=500 {print $7}' $A | cut -d'?' -f1 | sort | uniq -c | sort -rn
awk '$9 >= 500 {print $4; exit}' $A                     # [24/Aug/2026:09:02:30  (a 500)
awk '$9 == 503 {print $4; exit}' $A                     # [24/Aug/2026:09:13:15
```

Finding: 14 of 30 requests failed (47%). Isolated 500s on `/payment/transfer` from 09:02 (an app bug); total outage (503 on every `/payment` URL) from **09:13:15**.

**Step 2**

```bash
grep -E "09:1[3-6]" var/log/apache2/error.log
```

Finding: Apache is fine; the **backend on 127.0.0.1:8080 refused** connections, so the app server was down. (The 09:05 `504` was a timeout to core-banking via the app.)

**Step 3**

```bash
grep -B 3 -n FATAL opt/tomcat/logs/catalina.out
```

Timeline:
- 09:04–09:12 slow queries growing 2500 → 3200 → 4100 ms
- 09:13:14 DB pool exhausted (20/20 active, 31 waiting) → JVM out of heap → **payment-service exits**
- 09:14:30 auto-restart blocked: `lock file exists /run/payment.lock`

Also: 3 × `NullPointerException at TransferServlet.java:88` since 09:02 (separate code bug).

**Step 4**

```bash
diff -y --suppress-common-lines etc/payment/app-prod.properties etc/payment/app-staging.properties
```

Finding: production pool (20) and heap (512 MB) are far below what was tested in staging.

**Step 5**

```bash
find . -name "*.lock"
cat run/payment.lock
kill -0 4123 2>/dev/null && echo alive || echo "PID 4123 not running"     # 4123 = the pid= value inside the lock file
```

Careful: in the drill, `rebuild_index.sh` may have got a PID; compare with `pgrep -af java` (none). The lock belongs to the dead JVM → **stale**.

**Step 6**

```bash
ps aux --sort=-%cpu | head -n 3 | tee -a ~/incident/report.txt
kill $(pgrep -f rebuild_index); sleep 2; pgrep -f rebuild_index || echo stopped
```

Finding: `rebuild_index.sh` at 100% CPU, unrelated to payment, stopped with SIGTERM.

**Step 7**

```bash
du -sh . ; find . -type f -size +10M -exec ls -lh {} \;
gzip opt/tomcat/logs/catalina.2026-08-23.log
mkdir -p ~/for-developers && mv opt/tomcat/logs/heapdump-4123.hprof ~/for-developers/
du -sh .
```

Finding: ~196 MB → ~15 MB. The heap dump is evidence of the out-of-memory: kept for developers.

**Step 8**

```bash
diff -u backup/portal.conf.bak etc/apache2/sites-available/portal.conf
```

Finding: an untracked change. Portal pages would return **404** (folder does not exist). Explains the `/portal/sale.html` 404 pattern risk; not the payment outage.

**Step 9**

```bash
rm run/payment.lock
cp backup/portal.conf.bak etc/apache2/sites-available/portal.conf
diff -q backup/portal.conf.bak etc/apache2/sites-available/portal.conf && echo restored
```

(On a real server, after this: `apache2ctl configtest && systemctl reload apache2`, then `systemctl start` the app and watch `tail -F` until `Health check: OK`.)

Recommendation: `db.pool.maxTotal=100`, `jvm.heap.max=2048m` as tested in staging, via change ticket because it changes production capacity and memory.

**Step 10 · Escalations**

| Finding | Owner |
|---|---|
| `NullPointerException at TransferServlet.java:88` since 09:02 | **developers** (payment-service team) |
| slow queries on `txn` (2.5 → 4.1 s) | **database team** |
| core-banking read timeout at 09:05 (504) | **core-banking team** |
| scanner `10.0.0.203` probing `/wp-login.php`, `/.env` | **security team** |

**Report summary (model answer, 3 lines)**

> From 09:13 to (fix time) payment-service on lab-vm-01 was down: slow DB queries filled the 20-connection pool and the JVM ran out of its 512 MB heap; auto-restart was blocked by a stale lock file. Lock removed and service restarted; CPU hog stopped; 180 MB freed; unapproved Apache change reverted. Recommend production pool/heap sizes matching staging; code bug, slow queries and scanner escalated.
