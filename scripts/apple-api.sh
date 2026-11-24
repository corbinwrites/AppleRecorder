#!/usr/bin/env bash
# Look up an Apple / WhisperKit API instead of guessing.
# usage: scripts/apple-api.sh <symbol-or-regex> [Framework]
set -u
PAT="${1:?usage: apple-api.sh <symbol-or-regex> [Framework]}"
SDK="$(xcrun --show-sdk-path)"; FW="$SDK/System/Library/Frameworks"
if [ -n "${2:-}" ]; then ROOTS=("$FW/$2.framework")
else ROOTS=("$FW/FoundationModels.framework" "$FW/CoreAudio.framework" "$FW/CoreAudioTypes.framework" "$FW/AudioToolbox.framework" "$FW/AVFAudio.framework" "$FW/Speech.framework"); fi
echo "== swiftinterface (SDK)"
for r in "${ROOTS[@]}"; do [ -d "$r" ] && find "$r" -name '*.swiftinterface' ! -name '*.private.swiftinterface' -print0 | xargs -0 grep -nE "$PAT" 2>/dev/null; done | head -50
echo "== headers (SDK)"
for r in "${ROOTS[@]}"; do [ -d "$r" ] && find "$r" -path '*Headers*' -name '*.h' -print0 | xargs -0 grep -nE "$PAT" 2>/dev/null; done | head -50
echo "== SwiftPM checkouts (WhisperKit etc.)"
find . -path '*/.build/checkouts/*' -name '*.swift' -not -path '*/Tests/*' -print0 2>/dev/null | xargs -0 grep -nE "$PAT" 2>/dev/null | head -50
echo "== saved dumps"
grep -rnE "$PAT" docs/reference/sdk 2>/dev/null | head -30
