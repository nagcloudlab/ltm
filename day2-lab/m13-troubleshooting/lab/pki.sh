set -e
mkdir -p /tmp/pki && cd /tmp/pki && rm -rf *
mkdir db && touch db/index.txt && echo 1000 > db/serial
cat > ca.cnf <<'C'
[ca]
default_ca=CA
[CA]
dir=/tmp/pki
database=$dir/db/index.txt
serial=$dir/db/serial
new_certs_dir=$dir
default_md=sha256
policy=p
copy_extensions=copy
unique_subject=no
[p]
commonName=supplied
organizationName=optional
[v3_ca]
basicConstraints=critical,CA:true
keyUsage=critical,keyCertSign,cRLSign
[v3_leaf]
basicConstraints=CA:false
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:api.example.com
C
openssl req -x509 -newkey rsa:2048 -nodes -keyout root.key -out root.crt -days 3650 -subj "/O=PayBank/CN=PayBank Lab Root CA" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout int.key -out int.csr -subj "/O=PayBank/CN=PayBank Lab Issuing CA 1" 2>/dev/null
openssl ca -batch -config ca.cnf -cert root.crt -keyfile root.key -extensions v3_ca -startdate 20241114000000Z -enddate 20261114000000Z -in int.csr -out int.crt 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout api.key -out api.csr -subj "/O=PayBank/CN=api.example.com" -addext "subjectAltName=DNS:api.example.com" 2>/dev/null
openssl ca -batch -config ca.cnf -cert int.crt -keyfile int.key -extensions v3_leaf -startdate 20260101000000Z -enddate 20270630000000Z -in api.csr -out api.crt 2>/dev/null
openssl x509 -in api.crt -out api.pem; openssl x509 -in int.crt -out int.pem
cat api.pem int.pem > api-chain.crt
ls
