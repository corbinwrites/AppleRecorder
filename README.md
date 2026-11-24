# Apple Recorder
A vibecoded clone of Google Foresight that utilizes Apple Foundational Model or BYO AI

[![ci](https://github.com/corbinwrites/AppleRecorder/actions/workflows/ci.yml/badge.svg)](https://github.com/corbinwrites/AppleRecorder/actions/workflows/ci.yml)

Apple Recorder is a native macOS meeting recorder and note taker designed for local-first audio capture, on-device transcription, and AI-assisted note generation.

## Features
- **Three Capture Modes:** App + Microphone, App only, or Microphone only.
- **One Stereo File:** Synchronized dual-channel audio stored in a single file with app audio on the right channel and microphone on the left channel.
- **Local Transcription & Notes:** Powered on-device by WhisperKit and Apple Intelligence / Foundation Models.
- **Themes:** Editorial, Terminal, Focus, and System appearances.

## Privacy Statement
Your audio, transcripts, and notes never leave your Mac. Apple Recorder contains no telemetry, analytics, or background tracking. The only network request the application ever makes is the initial, one-time model download from Hugging Face for WhisperKit.

## Recording Consent Notice
Recording conversations may be subject to local, state, federal, or international wiretapping and consent laws. You must obtain consent from all participating parties before recording where required by applicable law.

## Installation
### Homebrew (Recommended)
```bash
brew install --cask corbinwrites/tap/apple-recorder
```

### Direct Download (DMG)
Download the latest DMG release from GitHub Releases. Because Apple Recorder is self-signed with a pinned certificate rather than notarized through Apple Developer ID:
1. Open the DMG and drag `AppleRecorder.app` into `/Applications`.
2. Right-click (or Control-click) `AppleRecorder.app` and choose **Open**.
3. In the security dialog, click **Open Anyway**.

### Build From Source
```bash
git clone https://github.com/corbinwrites/AppleRecorder.git
cd AppleRecorder
make setup-signing
make install
```

## Permissions & Troubleshooting
Apple Recorder requires **Microphone** and **Screen & System Audio Recording (Audio Only)** permissions.
If permissions become stale or revoked:
```bash
tccutil reset All io.github.corbinwrites.AppleRecorder
```

## Documentation & Spec
Full architecture and implementation details are specified in [docs/BUILD-GUIDE.md](docs/BUILD-GUIDE.md).

## License
MIT License. See [LICENSE](LICENSE) for details.
