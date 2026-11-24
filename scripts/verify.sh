#!/usr/bin/env bash
set -u
PKGS="Core Capture Transcribe Enhance Output Theme EditorKit Pipeline"
APP="build/Build/Products/Debug/AppleRecorder.app"
fail=0; printf "%-36s %s\n" "CHECK" "RESULT"
run() { local name="$1"; shift; local log="/tmp/ar_verify_${name//[^A-Za-z0-9]/_}.log"
  if "$@" >"$log" 2>&1; then printf "%-36s PASS\n" "$name"; else printf "%-36s FAIL  (log: %s)\n" "$name" "$log"; fail=1; fi; }
for p in $PKGS; do run "unit: $p" bash -c "cd Packages/$p && swift test"; done
run "tsan: Capture" bash -c "cd Packages/Capture && swift test --sanitize=thread"
run "realtime check" ./scripts/check-realtime.sh
run "spec tests untouched" ./scripts/protect-tests.sh
run "no secrets tracked" bash -c "! git ls-files | grep -E '\.p12\$|release-key\.pem\$|\.env\$'"
run "app build (strict concurrency)" make build
if [ "${1:-}" = "--selftests" ]; then
  for t in permissions finalize-synthetic mic-probe capture-tone transcribe-say enhance-synthetic; do
    out="/tmp/ar-selftest-$t.json"; rm -f "$out"
    open -W -n "$APP" --args --selftest "$t" --out "$out"
    s=$(plutil -extract status raw -o - "$out" 2>/dev/null || echo "missing")
    m=$(plutil -extract message raw -o - "$out" 2>/dev/null || echo "")
    printf "%-36s %s  %s\n" "selftest: $t" "$(echo "$s" | tr a-z A-Z)" "$m"
    [ "$s" = "fail" ] || [ "$s" = "missing" ] && fail=1
  done
fi
exit $fail
