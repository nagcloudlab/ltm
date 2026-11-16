#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p project-files/downloads
version=10.1.61
file="apache-tomcat-${version}.tar.gz"
base="https://archive.apache.org/dist/tomcat/tomcat-10/v${version}/bin"
curl --fail --location --retry 3 "$base/$file" -o "project-files/downloads/$file"
curl --fail --location --retry 3 "$base/$file.sha512" -o "project-files/downloads/$file.sha512"
(cd project-files/downloads && sha512sum -c "$file.sha512")
bash payment-app/update-checksums.sh
