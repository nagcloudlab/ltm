#!/usr/bin/env python3
# issuer.py - a tiny OAuth 2.0 token issuer for the lab.
#
# It supports one grant: client credentials (one program calling another program).
#   POST http://127.0.0.1:9000/token
#   form fields: grant_type=client_credentials, client_id, client_secret
#   answer: {"access_token": "<RS256 JWT>", "token_type": "Bearer", "expires_in": 300}
#
# It signs with YOUR private key: ~/lab/security/issuer/private.pem
# (you generate it in the lab; private keys never go into Git).
# Stop it with Ctrl+C.
import json
import os
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs

import jwt

ISSUER = "https://auth.example.com"
AUDIENCE = "payment-api"
LIFETIME = 300                                   # seconds a token stays valid
CLIENTS = {"mobile-app": "mobile-secret-456"}    # client_id -> client_secret (lab only)
PRIVATE_KEY = open(os.path.expanduser("~/lab/security/issuer/private.pem")).read()


class TokenHandler(BaseHTTPRequestHandler):
    def reply(self, code, body):
        data = (json.dumps(body) + "\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")   # tokens must not be cached
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path != "/token":
            return self.reply(404, {"error": "not_found"})
        length = int(self.headers.get("Content-Length", 0))
        form = {k: v[0] for k, v in parse_qs(self.rfile.read(length).decode()).items()}

        # 1. who is calling? (authentication of the client program)
        client_id = form.get("client_id")
        if client_id not in CLIENTS or CLIENTS[client_id] != form.get("client_secret"):
            return self.reply(401, {"error": "invalid_client"})
        # 2. which grant? only client credentials here
        if form.get("grant_type") != "client_credentials":
            return self.reply(400, {"error": "unsupported_grant_type"})

        # 3. build and sign the access token
        now = int(time.time())
        claims = {"iss": ISSUER, "sub": client_id, "aud": AUDIENCE,
                  "iat": now, "nbf": now, "exp": now + LIFETIME,
                  "jti": str(uuid.uuid4())}
        token = jwt.encode(claims, PRIVATE_KEY, algorithm="RS256")
        self.reply(200, {"access_token": token, "token_type": "Bearer",
                         "expires_in": LIFETIME})


print("Token issuer listening on http://127.0.0.1:9000/token", flush=True)
HTTPServer(("127.0.0.1", 9000), TokenHandler).serve_forever()
