#!/usr/bin/env python3
# check-jwt.py - verify a JWT the way a careful API should, using PyJWT.
#
# usage: python3 check-jwt.py <token> [leeway-seconds]
#
# Checks: signature, exp (expiry), nbf (not before), iat, iss and aud.
# HS256 tokens are checked with the shared lab secret;
# RS256 tokens with the issuer PUBLIC key in ~/lab/security/issuer/public.pem.
# leeway = how many seconds of clock difference we forgive (default 0).
import os
import sys

import jwt

SECRET = "paybank-lab-secret-do-not-reuse-1"
PUBLIC_KEY = os.path.expanduser("~/lab/security/issuer/public.pem")

token = sys.argv[1]
leeway = int(sys.argv[2]) if len(sys.argv) > 2 else 0

try:
    # Read the algorithm name, then pick the matching key ourselves.
    # Only these two pairs are allowed, so a token cannot choose its own key.
    alg = jwt.get_unverified_header(token).get("alg")
    if alg == "RS256":
        key = open(PUBLIC_KEY).read()
    else:
        alg, key = "HS256", SECRET
    claims = jwt.decode(token, key, algorithms=[alg],
                        audience="payment-api",
                        issuer="https://auth.example.com",
                        leeway=leeway)
    print("VALID:", claims)
except jwt.PyJWTError as e:
    print("REJECTED:", type(e).__name__, "-", e)
    sys.exit(1)
