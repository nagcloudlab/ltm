: > /usr/local/kong/logs/access.log; : > /usr/local/kong/logs/error.log; : > /var/log/nginx/payment-access.log; : > /var/log/nginx/payment-error.log
sleep 6; : > /opt/tomcat/logs/localhost_access_log.2026-11-15.txt; L=$(wc -l < /opt/tomcat/logs/catalina.out)
for i in 1 2 3 4; do curl -s -o /dev/null -X POST -H "apikey: demo-key-123" "localhost:8000/api/payment/slow?ms=70000" & done
sleep 3
( curl -si -H "apikey: demo-key-123" localhost:8000/api/payment/status > /tmp/user.txt ) &
sleep 8
echo "== direct"; curl -s -m 5 -w "%{http_code} %{time_total}\n" localhost:8080/payment/status; echo "rc=$?"
echo "== ss"; ss -tn state established "( sport = :8080 )" | head -12
echo "== dump"; kill -3 $(pgrep -f org.apache.catalina.startup.Bootstrap); sleep 3
tail -n +$L /opt/tomcat/logs/catalina.out | grep -A12 '"http-nio-8080-exec' | head -70
sleep 40; echo "== user"; cat /tmp/user.txt; echo
wait; sleep 30
echo "== kong"; cat /usr/local/kong/logs/access.log; grep -i "timed out" /usr/local/kong/logs/error.log | tail -2
echo "== nginx"; cat /var/log/nginx/payment-access.log; cat /var/log/nginx/payment-error.log
echo "== tomcat"; cat /opt/tomcat/logs/localhost_access_log.2026-11-15.txt
