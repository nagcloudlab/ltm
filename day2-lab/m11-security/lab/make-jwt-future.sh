#!/bin/bash
# ~/lab/make-jwt.sh   usage: ./make-jwt.sh <seconds-valid> [aud]
SECRET="paybank-lab-secret-do-not-reuse-1"
b64url() { openssl base64 -A | tr "+/" "-_" | tr -d "="; }
now=$(( $(date +%s) + 60 ))   # clock 60 s ahead
header='{"alg":"HS256","typ":"JWT"}'
payload="{\"iss\":\"https://auth.example.com\",\"sub\":\"mobile-app\","
payload+="\"aud\":\"${2:-payment-api}\",\"iat\":$now,\"exp\":$((now + ${1:-300}))}"
h=$(printf "%s" "$header"  | b64url)
p=$(printf "%s" "$payload" | b64url)
s=$(printf "%s" "$h.$p" | openssl dgst -sha256 -hmac "$SECRET" -binary | b64url)
echo "$h.$p.$s"
