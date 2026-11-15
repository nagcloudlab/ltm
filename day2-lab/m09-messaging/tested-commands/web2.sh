#!/bin/bash
r(){ echo; echo "\$ $*"; eval "$@" 2>&1; }
setsid python3 ~/stub.py >/tmp/stub.log 2>&1 < /dev/null &
for i in $(seq 1 60); do ss -lnt | grep -q ':8080 ' && break; sleep 1; done
r curl -si -X POST localhost:8080/payment/transfer
r time curl -sI localhost:8081/payment/transfer
r sudo tail -1 /var/log/nginx/error.log
echo ===DONE
