#!/bin/bash
# make-expired.sh - sign the SAME server request again, but with dates in the past
# (valid from 60 days ago until 30 days ago), so you can see an expired certificate.
# Run make-ca.sh first. Output: ~/lab/security/pki/expired-fullchain.crt
set -e
cd ~/lab/security/pki
start=$(date -u -d '60 days ago' +%Y%m%d%H%M%SZ)
end=$(date -u -d '30 days ago' +%Y%m%d%H%M%SZ)

# "openssl ca" can set exact start and end dates; it needs a tiny database
mkdir -p ca-db
touch ca-db/index.txt
[ -f ca-db/serial ] || echo 1000 > ca-db/serial
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
subjectAltName = DNS:portal.example.test
extendedKeyUsage = serverAuth
CNF
openssl ca -batch -config ca.cnf -cert int.crt -keyfile int.key -in server.csr \
    -out expired.crt -startdate "$start" -enddate "$end" -extensions srv -notext
cat expired.crt int.crt > expired-fullchain.crt
openssl x509 -in expired.crt -noout -subject -dates
