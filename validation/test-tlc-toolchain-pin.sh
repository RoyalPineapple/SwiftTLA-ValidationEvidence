#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/validation/tlc-toolchain.sh"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

curl --fail --location --proto '=https' --tlsv1.2 --silent --show-error \
  --header 'Accept: application/octet-stream' \
  --output "$temporary/tla2tools.jar" \
  "$TLC_RELEASE_ASSET_URL"

[ "$(shasum -a 256 "$temporary/tla2tools.jar" | awk '{print $1}')" = "$TLC_JAR_SHA256" ]
unzip -tqq "$temporary/tla2tools.jar"
