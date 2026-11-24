#!/usr/bin/env bash
set -euo pipefail
APP="${1:?usage: verify-signing.sh path/to/AppleRecorder.app}"
PIN="$(cat release-cert.sha1)"
fail() { echo "FAIL: $1"; exit 1; }
codesign --verify --deep --strict "$APP" || fail "signature invalid"
REQ="$(codesign -d -r- "$APP" 2>&1)"; echo "$REQ"
echo "$REQ" | grep -q 'cdhash' && fail "designated requirement is cdhash-based"
echo "$REQ" | grep -Eq 'certificate (leaf|root) = H"' || fail "no certificate hash in requirement"
TMP="$(mktemp -d)"; (cd "$TMP" && codesign -d --extract-certificates "$APP" >/dev/null 2>&1)
GOT="$(openssl x509 -inform DER -in "$TMP/codesign0" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
[ "$GOT" = "$PIN" ] || fail "signed with a different certificate ($GOT)"
codesign -dv "$APP" 2>&1 | grep -q 'flags=.*runtime' || fail "hardened runtime is off"
codesign -d --entitlements - "$APP" 2>&1 | grep -q 'com.apple.security.device.audio-input' || fail "audio-input entitlement missing"
for k in NSMicrophoneUsageDescription NSAudioCaptureUsageDescription; do
  /usr/libexec/PlistBuddy -c "Print :$k" "$APP/Contents/Info.plist" >/dev/null 2>&1 || fail "$k missing from Info.plist"
done
echo "PASS verify-signing"
