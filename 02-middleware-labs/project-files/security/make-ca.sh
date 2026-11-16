#!/bin/bash
# make-ca.sh - build a small private certificate chain for the lab:
#   root CA  ->  intermediate CA  ->  server certificate for portal.example.test
# Everything goes into ~/lab/security/pki. Keys stay on this laptop (never in Git).
set -e
mkdir -p ~/lab/security/pki
cd ~/lab/security/pki

# 1. Root CA: signs itself, valid 10 years. In real life it stays offline.
openssl req -x509 -newkey rsa:2048 -nodes -keyout root.key -out root.crt \
    -days 3650 -subj "/CN=PayBank Lab Root CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"

# 2. Intermediate CA: makes a request (CSR), the root signs it, valid 5 years.
openssl req -newkey rsa:2048 -nodes -keyout int.key -out int.csr \
    -subj "/CN=PayBank Lab Issuing CA 1"
printf 'basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n' > int.ext
openssl x509 -req -in int.csr -CA root.crt -CAkey root.key -out int.crt \
    -days 1825 -extfile int.ext

# 3. Server certificate: the intermediate signs it, valid 90 days.
#    Clients check the name in subjectAltName (SAN), not only the CN.
openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr \
    -subj "/CN=portal.example.test"
printf 'subjectAltName=DNS:portal.example.test\nextendedKeyUsage=serverAuth\n' > server.ext
openssl x509 -req -in server.csr -CA int.crt -CAkey int.key -out server.crt \
    -days 90 -extfile server.ext

# 4. What the web server sends: its own certificate first, then the intermediate.
cat server.crt int.crt > fullchain.crt
chmod 600 *.key
ls
