#!/bin/bash
r(){ echo; echo "\$ $*"; eval "$@" 2>&1; }
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null 2>&1
sudo tee /etc/nginx/sites-enabled/payment8081 >/dev/null <<'C'
server { listen 8081; location /payment/ { proxy_pass http://127.0.0.1:8080; proxy_read_timeout 10s; } }
C
sudo systemctl restart nginx
nohup python3 ~/stub.py >/dev/null 2>&1 &
sleep 2
r curl -i -X POST localhost:8080/payment/transfer
r time curl -I localhost:8081/payment/transfer
r sudo tail -1 /var/log/nginx/error.log
echo ===DONE
