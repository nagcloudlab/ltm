# 10 · Network

**Time:** 30 min

**Part A · Basics** on your own lab VM. **Part B · In depth** on the PayBank lab server (`~/lab/srv`, built by `00-setup.md`).


---

# Part A · Basics

## 10.1 · Network: IP, ports, who listens


```bash
ip addr
```

| Address | Meaning |
|---|---|
| `10.0.0.5` | your real network card: others use this |
| `127.0.0.1` | loopback, "localhost": the machine talking to itself |

### Which doors are open?

```bash
sudo ss -lntp
```

| Letter | Meaning |
|---|---|
| `l` | listening only |
| `n` | show numbers, not names |
| `t` | TCP |
| `p` | which process (needs sudo) |

| Listens on | From this server | From other machines |
|---|---|---|
| `0.0.0.0:22` | ✓ | ✓ |
| `127.0.0.53:53` | ✓ | ✕ |

- On Ubuntu 24.04 the process for port 22 may show as `systemd` (pid 1), not `sshd`: systemd holds the port (`ssh.socket`) and starts sshd when someone connects.
- `127.0.0.53:53` and `127.0.0.54:53` are the local DNS helper (Topic 10.5).

### Names to numbers

```bash
getent hosts localhost
cat /etc/hosts
```

Linux checks `/etc/hosts` first, then asks DNS.

### Knock on doors

```bash
ping -c 3 10.0.0.6               # your neighbour's VM
nc -vz 10.0.0.6 22
nc -vz localhost 9999
nc -vz -w 5 10.255.255.1 22
```

| Result | Speed | Means | Look at |
|---|---|---|---|
| succeeded | instant | someone listens | all good |
| refused | instant | machine up, nobody at that port | the service |
| timed out | after `-w 5` seconds | blocked or no route | firewall / network team |


---

# Part B · In depth: the PayBank lab server

```bash
cd ~/lab/srv
```

## 10.2 · curl: test a web service from the command line

```bash
curl -I http://localhost/            # headers only (after Module 3 installs Apache)
curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://localhost/
curl -v http://localhost:9999/
```

`curl` is the admin's browser; Module 3 teaches it fully. `-w` prints just the status and time: perfect for scripts. If curl stops at `* Trying`, the problem is network or port, not the web server.

## 10.3 · Listen yourself: a test port with `nc -l`

Terminal 1 (on your VM):

```bash
nc -l 9090
```

Terminal 2:

```bash
sudo ss -lntp | grep 9090
nc -vz localhost 9090
```

Your neighbour runs `nc -vz [your-vm-ip] 9090`: success proves the **network path** works before any real software is installed. Stop with `Ctrl+C` in Terminal 1.

## 10.4 · Routes: which way out?

```bash
ip route
```

| Line | Means |
|---|---|
| `10.0.0.0/24 dev ens33` | machines 10.0.0.x are on our own network: talk directly |
| `default via 10.0.0.1` | everything else goes to the **gateway** router 10.0.0.1 |

No `default` line = the server can reach only its own network.

```bash
tracepath -n 10.0.0.6
```

`tracepath` shows each router on the way; where it stops is where packets are lost.

## 10.5 · DNS: who answers names?

```bash
resolvectl status | grep -A2 "Current DNS"
cat /etc/resolv.conf
getent hosts ubuntu.com
resolvectl query ubuntu.com
```

Ubuntu sends DNS questions to a local helper (`127.0.0.53`, systemd-resolved, the `53` you saw in `ss`), which asks the real DNS server. `getent` follows the same order as programs: `/etc/hosts` first, then DNS.

## 10.6 · Connections right now

```bash
ss -tn | head
ss -s
```

`-l` shows **listening** doors; without `-l`, `ss -tn` shows **open conversations**. Thousands of `ESTAB` or `TIME-WAIT` lines on a web server = heavy traffic (Day 2 performance).

## 10.7 · The firewall on the server: `ufw`

```bash
sudo ufw status
```

Inactive on a fresh Ubuntu, so it is not the reason for timeouts in our lab. On company servers it is often active (Module 3, "works on the server, times out from the laptop").

---

## Exercises

1. `ping` to a server works, `nc -vz` to port 8080 says refused. Where is the problem?
2. Print only the HTTP status code of `http://localhost:9999/` with curl. What does it print and why?
3. Open port 9191 with `nc -l` and get your neighbour to reach it. Then close it and let them see `refused`.
4. What is your default gateway?
5. Which DNS server does your VM really use?

## Answers

1. The machine is up (ping works) but nothing listens on 8080: the service is stopped or on another port. Check `systemctl status` and `sudo ss -lntp`.
2. `curl -s -o /dev/null -w "%{http_code}\n" http://localhost:9999/` → `000`: no HTTP answer at all (refused).
3. `nc -l 9191` on yours; theirs `nc -vz [your-ip] 9191` → succeeded; after Ctrl+C → refused.
4. `ip route | grep default` → `via 10.0.0.1` (yours may differ).
5. `resolvectl status | grep "Current DNS"`.
