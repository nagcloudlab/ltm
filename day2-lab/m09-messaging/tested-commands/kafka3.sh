#!/bin/bash
r(){ echo; echo "\$ $*"; eval "$@" 2>&1; }
cd /opt/kafka
r bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
r bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group sms-check --from-beginning --max-messages 3 --formatter-property print.partition=true
r "printf 'ACC-1001:PaymentCreated PAY-7001\nACC-2002:PaymentCreated PAY-7002\nACC-1001:PaymentCompleted PAY-7001\nACC-2002:PaymentCompleted PAY-7002\nACC-1001:RefundIssued PAY-7001\n' | bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic payments --reader-property parse.key=true --reader-property key.separator=:"
r "bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic payments --group key-check --from-beginning --timeout-ms 20000 --formatter-property print.partition=true --formatter-property print.key=true | grep PAY-700"
r bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list
echo ===DONE
