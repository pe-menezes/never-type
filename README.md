<p align="center">
  <img src="assets/NeverTypeIcon.svg" width="112" height="112" alt="NeverType logo">
</p>

<h1 align="center">NeverType</h1>

<p align="center">
  Local voice dictation for macOS.<br>
  <sub>Audio, model and transcription stay on your Mac.</sub>
</p>

<p align="center"><a href="README.pt-BR.md">Português</a></p>

Hold a key in any application, speak, release, and the text appears where the
cursor is.

Around 600 ms per dictation with the model warm, on a MacBook Pro M4 Pro.

## What it does

Hold **Right ⌘**, speak, release. The transcription is pasted at the cursor.
Two quick taps lock the recording on so you can speak with the key up, one more
tap ends it, and Esc discards. The overlay stays a 34 px orb with the NeverType
mark. Its three bars move with the voice while listening, including hands-free,
then collapse into moving dots beside the unchanged cursor while writing text.

The menu bar menu offers Right ⌘, ⌥ and ⌃ as quick picks, and **Other key or
mouse button…** lets you press the key you want: any modifier on either side,
Fn, or a mouse button from the third on. What cannot be the key is refused on
the spot, with the reason on screen. A second key can lock hands-free with one
tap. The menu also holds the last 30 transcriptions and a custom vocabulary.
Clicking the orb opens that same menu, which is how you reach it in full screen.
[`docs/reference.md`](docs/reference.md) goes through every item, including the
table of accepted and refused keys.

## Requirements

- macOS 14 or later on Apple Silicon. The inference runs on the GPU through
  Metal. On the CPU the same inference is about 11× slower
  ([`docs/pitfalls.md`](docs/pitfalls.md)), which makes dictation unusable.
- Xcode Command Line Tools, which carry the Swift 6 toolchain the build uses.
  Full Xcode is optional.
- `cmake`, to build (`brew install cmake`).
- The model, 547 MB, which does not ship in the `.app`. A script downloads and
  converts it, or you copy the file from a machine that already has it.
- Portuguese speech only.

## Install

The repository ships source only, and each installation compiles on its own
machine.

```bash
bash scripts/build-app.sh   # the first build takes a few minutes
bash scripts/install.sh
```

On the first launch macOS asks for Microphone and Accessibility. The app needs
both. Until Accessibility is granted, a dictation attempt is blocked before
recording and an alert offers to open the right System Settings page.

[`docs/INSTALL.md`](docs/INSTALL.md) has the whole walkthrough, the model
included, and it was written for a coding agent to execute: send it the link to
this repository and ask it to follow that file.

## Privacy

The app opens no network connection at run time. The only download in the
project is the model, fetched by a script you run by hand.

The app writes to `~/Library/Application Support/NeverType/`, unencrypted: the
last 30 transcriptions (`historico.json`), the audio of the last dictation
(`last.wav`), a log with the time and size of each transcription, and your
vocabulary. **Clear History**, in the menu, deletes the first two. Insertion goes
through the clipboard, so the text sits there for 0.6 s, marked as concealed,
before your previous contents come back.

The no-network claim is checked by hand, and the repository has no CI.
[`docs/reference.md`](docs/reference.md) gives the grep, the two commands for the
binary side, and what nobody has run.

## Limitations

- Another language means editing `Transcriber.swift` and rebuilding, and quality
  outside Portuguese was never measured
  ([`docs/model-choice.md`](docs/model-choice.md)).
- A dictation past 30 s pays for a second Whisper window: 31 s measured 1299 ms.
  Above two windows nobody has measured.
- A Bluetooth headset records at 8 kHz, which macOS switches to when the
  microphone opens, and recognition gets worse. The Mac's own microphone avoids
  the downgrade.
- The app is signed with a local certificate, so anyone who already runs code as
  you on this machine can sign as NeverType and inherit its Microphone and
  Accessibility permissions ([`docs/reference.md`](docs/reference.md)).

## Development

```bash
bash scripts/build-app.sh     # compiles whisper.cpp into vendor/
swift build && swift test     # 154 tests, in swift-testing
```

`vendor/` is not versioned. Without it the build fails with `could not build
Objective-C module 'CWhisper'`, a message that does not say the cause.

- [`docs/pitfalls.md`](docs/pitfalls.md): the 24 things that broke here, with the
  measured cost of each.
- [`docs/model-choice.md`](docs/model-choice.md): why `large-v3-turbo`, with the
  numbers.
- [`docs/launch-at-login.md`](docs/launch-at-login.md): what opening at login
  costs, measured.
- [`docs/reference.md`](docs/reference.md): the menu, the files on disk, the two
  settings with no menu item, the signing.

## License

MIT. Depends on [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT) and
on OpenAI's Whisper model (MIT, code and weights).
