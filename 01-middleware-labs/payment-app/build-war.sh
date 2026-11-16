#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${TOMCAT_HOME:?Set TOMCAT_HOME to an extracted Tomcat 10.1 directory}"
command -v javac >/dev/null
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "$build_dir/good/WEB-INF/classes" "$build_dir/broken/WEB-INF" "$build_dir/broken/META-INF"
javac --release 11 -cp "$TOMCAT_HOME/lib/servlet-api.jar" -d "$build_dir/good/WEB-INF/classes" payment-app/src/PaymentServlet.java
cp payment-app/web.xml "$build_dir/good/WEB-INF/web.xml"
cp payment-app/web.xml "$build_dir/broken/WEB-INF/web.xml"
printf '%s\n' '<Context failCtxIfServletStartFails="true"/>' > "$build_dir/broken/META-INF/context.xml"
jar --create --file project-files/apps/payment.war -C "$build_dir/good" .
jar --create --file project-files/apps/payment-broken.war -C "$build_dir/broken" .
echo 'Built good WAR and intentionally broken WAR (missing servlet class).'
