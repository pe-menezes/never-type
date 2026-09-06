<p align="center">
  <img src="assets/NeverTypeIcon.svg" width="112" height="112" alt="NeverType logo">
</p>

<h1 align="center">NeverType</h1>

<p align="center">
  Local voice dictation for macOS.<br>
  <sub>Audio, model and transcription stay on your Mac.</sub>
</p>

<p align="center"><a href="README.pt-BR.md">Português</a></p>

<p align="center">
  <a href="https://github.com/pe-menezes/never-type/actions/workflows/ci.yml"><img src="https://github.com/pe-menezes/never-type/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

Hold **Right ⌘**, speak in Portuguese, and release to paste the transcription
at the cursor. NeverType runs in the menu bar and transcribes on your Mac using
Whisper, with no network access during use.

Short dictations measured about **600 ms** with the model warm on a MacBook Pro
M4 Pro. See the [model comparison](docs/model-choice.md) for measurements and
coverage.

## Features

- Hold to record, or double-tap to speak hands-free. Tap again to finish; Esc
  discards the recording.
- Choose a supported modifier key, Fn or an extra mouse button from the menu.
  An optional second key starts hands-free recording with one tap.
- A floating indicator shows recording activity and transcription progress.
  Click it to open the menu, including in full-screen apps.
- Copy recent transcriptions, add vocabulary hints and text replacements, or
  enable launch at login.

Wait for transcription to finish before starting another dictation.

The [reference](docs/reference.md) covers controls, accepted keys and settings.

## Requirements

- Apple Silicon Mac running macOS 14 or later.
- Swift 6.0.3 or later, supplied by Xcode Command Line Tools or Xcode.
- `cmake` for the build. Model setup also needs Homebrew and Python 3.
- The 547 MB Whisper model, stored separately from the app.

## Install

NeverType currently ships as source. Installation compiles the app locally and
creates a local signing certificate.

With the prerequisites installed:

```bash
git clone https://github.com/pe-menezes/never-type.git
cd never-type
bash scripts/setup-bench.sh  # downloads dependencies and converts three models
bash scripts/fetch-model.sh  # installs the model NeverType uses
bash scripts/install.sh     # builds, signs, installs and opens the app
```

Model setup can take a while and downloads more than the final 547 MB model.
If you already have a compatible model file, the
[installation guide](docs/INSTALL.md#3-the-model) explains how to use it.

Grant **Microphone** and **Accessibility** when macOS asks, then dictate into a
text field to verify the installation. The [installation guide](docs/INSTALL.md)
has the complete walkthrough, troubleshooting and update instructions; a coding
agent can follow it too.

## Privacy

The installed app makes no network requests. Build, model setup and update
scripts download source code, dependencies and model files when you run them.

NeverType stores the last 30 transcriptions, the last dictation's audio, your
vocabulary and a diagnostic log in `~/Library/Application Support/NeverType/`,
without app-level encryption. The log records transcription timing and size,
not the text. **Clear History** deletes the stored transcriptions and audio.

Insertion uses the clipboard. By default, the previous clipboard contents are
restored after 0.6 s, provided the clipboard has not changed in the meantime.
If automatic pasting is blocked, the transcription stays on the clipboard for
manual pasting. Dictated text is marked as concealed, but clipboard managers
that ignore that mark can retain it. Explicitly copying a history item leaves
it on the clipboard.

The network claim is based on manual source inspection; CI does not verify it.
The [reference](docs/reference.md#the-check-behind-no-network-at-run-time)
documents the checks and their limits.

## Limitations

- Portuguese is the configured language. Using another language requires a code
  change and rebuild; recognition quality outside Portuguese has not been measured.
- Longer recordings take longer to transcribe: 404 s of speech measured about
  13 s. The floating indicator shows progress during transcription.
- Bluetooth microphone modes can reduce audio quality. Use the Mac microphone
  if headset recordings produce poor results.
- The local signing certificate can be used by other code running as your user
  to impersonate NeverType and inherit its permissions. See
  [signing](docs/reference.md#signing-and-what-it-costs).

## Development

```bash
bash scripts/build-app.sh  # builds the native whisper.cpp dependency and app
swift build && swift test # swift-testing
```

The generated `vendor/` directory is required before running SwiftPM directly.
Model and audio integration tests are conditional; a passing run without those
assets does not exercise transcription.

- [Technical reference](docs/reference.md): architecture, controls and storage.
- [Model choice](docs/model-choice.md): quality and latency measurements.
- [Pitfalls](docs/pitfalls.md): failures encountered and their fixes.
- [Launch at login](docs/launch-at-login.md): startup measurements.
- [Bench fixtures](fixtures/README.md): recording samples for local evaluation.

## License

MIT. Depends on [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT) and
OpenAI's Whisper model (MIT, code and weights).
