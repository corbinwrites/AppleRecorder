#!/usr/bin/env bash
# scripts/sign-release.sh <path/to/AppleRecorder.app>
set -euo pipefail
APP="$1"; KC="$RUNNER_TEMP/sign.keychain-db"; PIN="$(cat release-cert.sha1)"
echo "$MAC_SIGN_P12" | base64 -d > "$RUNNER_TEMP/release.p12"
security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings -lut 21600 "$KC"
security unlock-keychain -p "$KC_PASS" "$KC"
security import "$RUNNER_TEMP/release.p12" -k "$KC" -P "$MAC_SIGN_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KC" >/dev/null
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')

# Pin: refuse any other certificate
IMPORTED="$(openssl pkcs12 -in "$RUNNER_TEMP/release.p12" -passin env:MAC_SIGN_PASSWORD -nokeys -clcerts \
  | openssl x509 -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
[ "$IMPORTED" = "$PIN" ] || { echo "Wrong certificate. Aborting."; exit 1; }

# Inside-out: nested code first, then the app
find "$APP/Contents" \( -name "*.dylib" -o -name "*.framework" -o -name "*.xpc" \) -print0 \
  | xargs -0 -n1 codesign --force --options runtime --timestamp=none --sign "$PIN" --keychain "$KC"
codesign --force --options runtime --timestamp=none --sign "$PIN" --keychain "$KC" \
  --entitlements App/AppleRecorder.entitlements "$APP"

# Assert identity-based DR, never cdhash
REQ="$(codesign -d -r- "$APP" 2>&1)"; echo "$REQ"
echo "$REQ" | grep -q 'cdhash' && { echo "DR is cdhash-based: not signed with the release cert"; exit 1; }
echo "$REQ" | grep -Eq 'certificate (leaf|root) = H"' || { echo "DR has no certificate hash"; exit 1; }
codesign --verify --deep --strict "$APP"
