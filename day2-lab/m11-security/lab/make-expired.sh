#!/bin/bash
# ~/lab/make-expired.sh : sign server.csr again with fixed past dates (1 Aug - 1 Nov 2026)
set -e
cd ~/lab/pki
mkdir -p ca-db; touch ca-db/index.txt; [ -f ca-db/serial ] || echo 1000 > ca-db/serial
cat > ca.cnf <<'CNF'
[ ca ]
default_ca = int
[ int ]
database = ca-db/index.txt
serial = ca-db/serial
new_certs_dir = ca-db
default_md = sha256
policy = any
unique_subject = no
[ any ]
commonName = supplied
[ srv ]
subjectAltName = DNS:payment.example.com
extendedKeyUsage = serverAuth
CNF
openssl ca -batch -config ca.cnf -cert int.crt -keyfile int.key -in server.csr -out expired.crt \
    -startdate 20260801000000Z -enddate 20261101000000Z -extensions srv
cat expired.crt int.crt > expired-fullchain.crt
openssl x509 -in expired.crt -noout -dates
