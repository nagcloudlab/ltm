#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../project-files"
find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
