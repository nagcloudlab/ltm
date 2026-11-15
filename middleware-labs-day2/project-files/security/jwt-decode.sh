#!/bin/bash
# jwt-decode.sh - show the header and the payload of a JWT as pretty JSON.
# usage: ./jwt-decode.sh <token>
# It only DECODES. It does not check the signature: anyone can read a JWT.
for i in 1 2; do
  part=$(cut -d. -f"$i" <<<"$1")
  # base64url drops the = padding; put it back so the decoder accepts the text
  case $(( ${#part} % 4 )) in 2) part+="==";; 3) part+="=";; esac
  basenc --base64url -d <<<"$part" | jq .
done
