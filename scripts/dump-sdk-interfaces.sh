#!/usr/bin/env bash
# Run once on the Mac (needs Xcode). Copies the API surfaces agents need into docs/reference/sdk/ so they can read them offline.
# Commit the result. Re-run after an Xcode / SDK update.
set -eu
cd "$(git rev-parse --show-toplevel)"
SDK="$(xcrun --show-sdk-path)"; FW="$SDK/System/Library/Frameworks"; OUT="docs/reference/sdk"
rm -rf "$OUT"; mkdir -p "$OUT"
echo "SDK: $SDK" > "$OUT/SDK-VERSION.txt"; xcodebuild -version >> "$OUT/SDK-VERSION.txt"; sw_vers >> "$OUT/SDK-VERSION.txt"
for f in FoundationModels Speech; do
  find "$FW/$f.framework" -name '*.swiftinterface' ! -name '*.private.swiftinterface' | head -1 | while read -r p; do cp "$p" "$OUT/$f.swiftinterface"; done
done
mkdir -p "$OUT/CoreAudio-headers"
for f in CoreAudio CoreAudioTypes; do
  [ -d "$FW/$f.framework/Headers" ] && cp "$FW/$f.framework/Headers/"*.h "$OUT/CoreAudio-headers/" 2>/dev/null || true
done
# Process tap + aggregate device headers live in CoreAudio; AudioToolbox has ExtAudioFile
mkdir -p "$OUT/AudioToolbox-headers"
cp "$FW/AudioToolbox.framework/Headers/ExtendedAudioFile.h" "$OUT/AudioToolbox-headers/" 2>/dev/null || true
du -sh "$OUT"; echo "Now: git add $OUT && git commit -m 'docs: SDK API dumps'"
echo "WhisperKit: after 'swift package resolve' in Packages/Transcribe, apple-api.sh greps .build/checkouts automatically."
