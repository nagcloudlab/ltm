#!/bin/bash
# usage: ./jwt-decode.sh <token>     prints header, then payload
for i in 1 2; do
  part=$(cut -d. -f$i <<<"$1")
  case $(( ${#part} % 4 )) in 2) part+="==";; 3) part+="=";; esac
  basenc --base64url -d <<<"$part" | jq .
done
