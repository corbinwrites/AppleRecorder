# AppleRecorder
A vibecoded clone of Google Foresight that utilizes Apple Foundational Model or BYO AI

**Status: pre-alpha. Under construction.** The full spec and build plan are in [`docs/BUILD-GUIDE.md`](docs/BUILD-GUIDE.md).

Apple Recorder is a native macOS (26+, Apple silicon) meeting recorder and note app.

- Records one app (for example Discord), your microphone, or both. Room meetings work in mic-only mode.
- Saves one stereo `.m4a` (left = mic, right = app) or a mono file for single-source recordings.
- Transcribes on your Mac with WhisperKit, then writes notes with Apple's on-device Foundation Models.
- Writes plain Markdown and audio to two folders you choose. No cloud, no account.
- Obsidian-style Markdown editor, Liquid Glass UI, themes (Gruvbox, Dracula, Nord, Tokyo Night, Catppuccin, Solarized, Sacred).

## Privacy
Audio and transcripts never leave your Mac. The only network use is the one-time model download from Hugging Face.

## Recording consent
Recording laws vary. California and many other states require **all-party consent** for confidential conversations. You are the person recording. Tell everyone present before you press Record. This is not legal advice. See [`CONSENT.md`](CONSENT.md).

## Install
Not released yet. Planned: Homebrew tap (`brew install --cask corbinwrites/tap/apple-recorder`), a DMG on GitHub Releases, or build from source. Releases are self-signed, not notarized. See the build guide, section 17.

## License
MIT. See [`LICENSE`](LICENSE) and [`THIRD-PARTY-LICENSES.md`](THIRD-PARTY-LICENSES.md).
