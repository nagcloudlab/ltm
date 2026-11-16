#!/bin/bash
# make-jwt.sh - build a JWT with plain bash + openssl, print it on one line.
#
# usage: ./make-jwt.sh <valid-seconds> [aud] [start-offset-seconds]
#   valid-seconds         exp = start + this (a negative number makes an expired token)
#   aud                   audience claim (default: payment-api)
#   start-offset-seconds  iat and nbf = now + this (default 0; use 60 to act like
#                         an issuer whose clock is 60 seconds ahead of yours)
#
# Signing:
#   default     HS256 with the shared lab secret below (both sides know the secret)
#   ALG=RS256   RS256 with the private key in ~/lab/security/issuer/private.pem
#
# Classroom secret only. Never reuse it anywhere real.
SECRET="paybank-lab-secret-do-not-reuse-1"
KEY=~/lab/security/issuer/private.pem
ALG=${ALG:-HS256}

# base64url = base64 with - and _ instead of + and /, and no = padding
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

start=$(( $(date +%s) + ${3:-0} ))
exp=$(( start + ${1:?usage: ./make-jwt.sh <valid-seconds> [aud] [start-offset-seconds]} ))

header="{\"alg\":\"$ALG\",\"typ\":\"JWT\"}"
payload="{\"iss\":\"https://auth.example.com\",\"sub\":\"mobile-app\",\"aud\":\"${2:-payment-api}\","
payload+="\"iat\":$start,\"nbf\":$start,\"exp\":$exp}"

h=$(printf '%s' "$header"  | b64url)
p=$(printf '%s' "$payload" | b64url)

# the signature covers "header.payload" exactly as encoded above
if [ "$ALG" = "RS256" ]; then
  s=$(printf '%s' "$h.$p" | openssl dgst -sha256 -sign "$KEY" -binary | b64url)
else
  s=$(printf '%s' "$h.$p" | openssl dgst -sha256 -hmac "$SECRET" -binary | b64url)
fi
echo "$h.$p.$s"
