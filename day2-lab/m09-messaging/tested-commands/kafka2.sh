#!/bin/bash
r(){ echo; echo "\$ $*"; eval "$@" 2>&1; }
B=/opt/kafka/bin
r timeout 30 $B/kafka-topics.sh --bootstrap-server localhost:9093 --list
r timeout 30 $B/kafka-topics.sh --bootstrap-server localhost:9999 --list
r sudo systemctl stop kafka
r timeout 30 $B/kafka-topics.sh --bootstrap-server localhost:9092 --list
r sudo systemctl start kafka
echo ===DONE
