# 01 · HTTP basics

**Time:** 35 min

**You will learn:** what a web server does, what travels in an HTTP request and response, methods, headers, the first status codes, how to read a URL, and how to see a real request with your own eyes.

---

## 01.1 · What a web server does

```
 Browser / curl                 Web server (Apache)              Disk
 ───────────────               ─────────────────────            ─────────────────────
 "GET /hello.html" ───────────► listens on port 80   ──reads──► /var/www/html/hello.html
                    ◄────────── "200 OK" + the page
```

A web server is **a service** (topic 08 of the Linux handout) that:

1. listens on a port (80 for http)
2. reads each request
3. finds the file (or asks an application, later in the course)
4. sends back a response with a **status code**
5. writes one line in its log

## 01.2 · HTML vs HTTP

| | HTML | HTTP |
|---|---|---|
| is | the **page**: headings, text, links | the **delivery**: how to ask for it and send it |
| like | the letter | the envelope and the postal rules |
| who cares | developers | **admins**: requests, responses, status codes, logs |

## 01.3 · See a real request: be the server yourself

You do not need Apache for this. Open **two terminals** on your VM.

Terminal 1: a fake "server" that just prints whatever arrives on port 9000:

```bash
nc -l 9000
```

Terminal 2: send a request with curl:

```bash
curl http://localhost:9000/hello.html
```

Terminal 1 now shows the request curl sent:

```
GET /hello.html HTTP/1.1
Host: localhost:9000
User-Agent: curl/8.5.0
Accept: */*
```

Now answer as the server. In **Terminal 1**, type these lines, then press `Enter` on an empty line, then `Ctrl+C`:

```
HTTP/1.1 200 OK
Content-Type: text/plain

Hello from my fake server
```

Terminal 2 shows `Hello from my fake server`. You just did the web server's whole job by hand.

## 01.4 · Inside a request

```
GET /hello.html HTTP/1.1        ← request line: METHOD  PATH  VERSION
Host: localhost:9000            ← headers: one per line, Name: value
User-Agent: curl/8.5.0
Accept: */*
                                ← empty line: end of headers
(body: only for POST/PUT)
```

| Part | Example | Means |
|---|---|---|
| method | `GET` | what to do |
| path | `/hello.html` | which page |
| version | `HTTP/1.1` | protocol version |
| `Host` header | `localhost:9000` | which **website** (important for virtual hosts, topic 05) |

## 01.5 · Methods

| Method | Means | Data travels | Example |
|---|---|---|---|
| `GET` | give me this | in the URL after `?` | `GET /search?q=tomcat` |
| `POST` | here is data, process it | in the **body** | logins, payments, forms |
| `HEAD` | like GET, headers only | — | what `curl -I` sends |
| `PUT` / `DELETE` | replace / delete | body | used by APIs |
| `OPTIONS` | what may I do here? | — | browsers before cross-site calls |

```bash
curl -X POST -d "amount=500" http://localhost:9000/pay
```

(Run `nc -l 9000` in Terminal 1 first. You will see the body `amount=500` after the headers, and a `Content-Length: 10` header.)

## 01.6 · Inside a response

```
HTTP/1.1 200 OK                 ← status line: VERSION  CODE  TEXT
Content-Type: text/html         ← headers
Content-Length: 21
Server: Apache/2.4.58 (Ubuntu)
                                ← empty line
<h1>Hello</h1>                  ← body: the page
```

## 01.7 · Headers you will meet every day

| Request header | Means | Response header | Means |
|---|---|---|---|
| `Host` | which website | `Content-Type` | kind of file: `text/html`, `image/png` |
| `User-Agent` | which program asks | `Content-Length` | size in bytes |
| `Accept` | what it understands | `Server` | which software answered |
| `Cookie` | "it's me again" | `Set-Cookie` | "remember this token" |
| `Accept-Encoding` | "I can unzip gzip" | `Location` | "go here instead" (redirects) |

**Cookies in one line:** HTTP forgets you after every request. After login the server sends `Set-Cookie: session=7f3a9`; the browser sends `Cookie: session=7f3a9` on every later request, like a cloakroom token.

## 01.8 · Status codes: the first digit tells the family

| Family | Means | You will cause |
|---|---|---|
| **2xx** | it worked | 200 OK, 206 Partial Content |
| **3xx** | go somewhere else | 301, 302, 304 |
| **4xx** | the **request** is the problem | 400, 401, 403, 404, 405, 413, 414 |
| **5xx** | the **server** is the problem | 500, 502, 503, 504 |

Start with two:

| Code | Means |
|---|---|
| **200 OK** | here is your page |
| **404 Not Found** | the server is fine, but nothing exists at that path |

A 404 is **not** "the server is down": the server answered.

## 01.9 · Reading a URL

```
http://portal.example.com:80/payment/status?acct=1234
└┬─┘   └───────┬────────┘ └┤ └──────┬──────┘ └───┬───┘
scheme       host        port     path         query
```

| Part | Means | Topic |
|---|---|---|
| scheme | `http` (port 80) or `https` (port 443, encrypted, topic 12) | |
| host | name → IP via `/etc/hosts` or DNS | Linux 10 |
| port | the door; left out = 80 for http | Linux 10 |
| path | which page; becomes a file path on disk | 04 |
| query | extra data after `?`, `&` between items | |

## 01.10 · The journey of one request (where things fail)

| Step | What happens | If it fails you see |
|---|---|---|
| 1 Find the address | name → IP | `Could not resolve host` |
| 2 Connect | open TCP to port 80 | `Couldn't connect to server` (refused) / timed out |
| 3 Ask | send the request | — |
| 4 Answer | status + headers + body | 404, 403, 500 … |
| 5 Draw | browser shows the HTML | blank or broken page |

Steps 1–2 failing = Apache never saw the request (look at name, service, port, firewall). Step 4 = Apache answered, so **its logs** know why.

---

## Exercises

1. With `nc -l 9000`, send `curl -I http://localhost:9000/x`. Which method arrives?
2. Send a request with a custom header `X-Trainee: yourname` and find it in the `nc` terminal.
3. In `https://shop.example.com:8443/cart?id=7&qty=2`, name the scheme, host, port, path and query.
4. A user says "the site gives 404, the server is down". Correct them in one sentence.
5. Which header tells Apache which website you want?

## Answers

1. `HEAD /x HTTP/1.1`.
2. `curl -H "X-Trainee: yourname" http://localhost:9000/` → the line `X-Trainee: yourname` appears among the headers.
3. scheme `https`, host `shop.example.com`, port `8443`, path `/cart`, query `id=7&qty=2`.
4. A 404 means the server is up and answered; only the page at that path does not exist.
5. `Host`.
