#!/bin/bash
# fill-kong-key.sh - make your own copy of Kong stage 5 with YOUR issuer public key.
# reads : ~/ltm/middleware-labs-day2/project-files/kong/05-jwt.yml (has a placeholder line)
#         ~/lab/security/issuer/public.pem                       (made in the lab)
# writes: ~/lab/security/05-jwt.yml                               (ready for Kong)
set -e
STAGE=~/ltm/middleware-labs-day2/project-files/kong/05-jwt.yml
PUB=~/lab/security/issuer/public.pem
OUT=~/lab/security/05-jwt.yml

# YAML needs every key line indented under "rsa_public_key: |" (10 spaces here)
indented=$(sed 's/^/          /' "$PUB")
awk -v key="$indented" '/__ISSUER_PUBLIC_KEY__/ { print key; next } { print }' "$STAGE" > "$OUT"
echo "wrote $OUT"
