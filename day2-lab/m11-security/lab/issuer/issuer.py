#!/usr/bin/env python3
# Tiny OAuth 2.0 token issuer for the lab (client-credentials grant only).
# POST /token  -> signed RS256 JWT access token
# GET  /.well-known/jwks.json -> public key in JWKS form
import base64, json, time, uuid, jwt
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs

ISSUER = "https://auth.example.com"
CLIENTS = {"mobile-app": "mobile-secret-456"}       # client_id: client_secret
PRIVATE = open("/home/student/lab/issuer/private.pem").read()
PUBLIC = open("/home/student/lab/issuer/public.pem").read()
KID = "lab-key-1"
LIFETIME = 300

class H(BaseHTTPRequestHandler):
    def reply(self, code, body, extra=None):
        b = (json.dumps(body, indent=2) + "\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/.well-known/jwks.json":
            rsa = jwt.algorithms.RSAAlgorithm(jwt.algorithms.RSAAlgorithm.SHA256)
            jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(rsa.prepare_key(PUBLIC)))
            jwk.update({"kid": KID, "use": "sig", "alg": "RS256"})
            return self.reply(200, {"keys": [jwk]})
        self.reply(404, {"error": "not_found"})

    def do_POST(self):
        if self.path != "/token":
            return self.reply(404, {"error": "not_found"})
        n = int(self.headers.get("Content-Length", 0))
        form = {k: v[0] for k, v in parse_qs(self.rfile.read(n).decode()).items()}
        cid, csec = form.get("client_id"), form.get("client_secret")
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Basic "):
            cid, _, csec = base64.b64decode(auth[6:]).decode().partition(":")
        if CLIENTS.get(cid) is None or CLIENTS[cid] != csec:
            return self.reply(401, {"error": "invalid_client"},
                              {"WWW-Authenticate": 'Basic realm="auth.example.com"'})
        if form.get("grant_type") != "client_credentials":
            return self.reply(400, {"error": "unsupported_grant_type"})
        now = int(time.time())
        claims = {"iss": ISSUER, "sub": cid, "aud": "payment-api",
                  "iat": now, "nbf": now, "exp": now + LIFETIME,
                  "scope": form.get("scope", "payments:read"), "jti": str(uuid.uuid4())}
        token = jwt.encode(claims, PRIVATE, algorithm="RS256", headers={"kid": KID})
        self.reply(200, {"access_token": token, "token_type": "Bearer",
                         "expires_in": LIFETIME, "scope": claims["scope"]})

HTTPServer(("127.0.0.1", 9000), H).serve_forever()
