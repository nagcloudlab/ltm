#!/bin/bash
# Print test PaymentCompleted events as "key:value" lines for kafka-console-producer.sh.
# Usage: gen-payments.sh COUNT [KEY]
#   COUNT  how many events to print (default 10)
#   KEY    account number to use for every event (default: a random acc-1000 ... acc-1049)
# Example: gen-payments.sh 3 acc-1001
count=${1:-10}
fixed_key=$2
batch=$(date +%H%M%S)   # time of this run, so every run makes new payment ids
for i in $(seq 1 "$count"); do
  key=${fixed_key:-acc-$((RANDOM % 50 + 1000))}
  echo "$key:{\"event\":\"PaymentCompleted\",\"id\":\"PAY-$batch-$i\",\"amount\":500}"
done
