#!/usr/bin/env bash
set -euo pipefail
APP="${1:?usage: sign-local.sh path/to/AppleRecorder.app}"
NAME="AppleRecorder Local Dev"
# Sign by SHA-1: an untrusted self-signed cert is hidden by `find-identity -v`.
ID="$(security find-identity -p codesigning | awk -v n="$NAME" 'index($0, n) { print $2; exit }')"
if [ -z "$ID" ]; then
  echo "WARNING: no '$NAME' identity. Signing ad-hoc: permissions reset on every rebuild. Run: make setup-signing" >&2
  ID="-"
fi
find "$APP/Contents" \( -name "*.dylib" -o -name "*.framework" -o -name "*.xpc" \) -print0 \
  | xargs -0 -n1 codesign --force --options runtime --timestamp=none --sign "$ID"
codesign --force --options runtime --timestamp=none --sign "$ID" --entitlements App/AppleRecorder.entitlements "$APP"
codesign --verify --deep --strict "$APP" && echo "signed with: $ID"
