#!/bin/bash
# ~/lab/make-ca.sh : root CA -> intermediate CA -> server cert for payment.example.com
set -e
mkdir -p ~/lab/pki && cd ~/lab/pki
# 1 root CA, 10 years, signs itself
openssl req -x509 -newkey rsa:2048 -nodes -keyout root.key -out root.crt \
    -days 3650 -subj "/CN=PayBank Lab Root CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
# 2 intermediate: a request, then the root signs it
openssl req -newkey rsa:2048 -nodes -keyout int.key -out int.csr \
    -subj "/CN=PayBank Lab Issuing CA 1"
printf 'basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n' > int.ext
openssl x509 -req -in int.csr -CA root.crt -CAkey root.key -out int.crt \
    -days 1825 -extfile int.ext
# 3 server key + CSR
openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr \
    -subj "/CN=payment.example.com"
printf 'subjectAltName=DNS:payment.example.com\nextendedKeyUsage=serverAuth\n' > server.ext
openssl x509 -req -in server.csr -CA int.crt -CAkey int.key -out server.crt \
    -days 90 -extfile server.ext
# 4 what Nginx sends: server first, then intermediate
cat server.crt int.crt > fullchain.crt
ls
