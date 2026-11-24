#!/usr/bin/env bash
set -euo pipefail
V="${1:?version, e.g. 1.0.0}"; ZIP="${2:?path to AppleRecorder-$V.zip}"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
cat <<EOF
cask "apple-recorder" do
  version "$V"
  sha256 "$SHA"
  url "https://github.com/corbinwrites/AppleRecorder/releases/download/v#{version}/AppleRecorder-#{version}.zip"
  name "Apple Recorder"
  desc "Local meeting recorder and note taker"
  homepage "https://github.com/corbinwrites/AppleRecorder"
  depends_on macos: ">= :tahoe"
  app "AppleRecorder.app"
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/AppleRecorder.app"]
  end
  caveats "This app is self-signed, not notarized. The cask removes the quarantine flag on install."
end
EOF
