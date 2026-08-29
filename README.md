Português: [README.pt-BR.md](README.pt-BR.md)

# NeverType

Voice dictation that never leaves your machine. Hold a key in any application,
speak, release, and the text appears where the cursor is.

**~600 ms** per dictation, on a MacBook Pro M4 Pro. No network calls.

## Why it exists

Voice dictation tools usually send the audio to a server. That is what makes
them fast, and also what rules them out wherever the content cannot leave the
machine.

NeverType runs the model locally. The audio is born and dies on your Mac; the
model sits on disk; the app opens no connection at run time: there is no network
API in the code and no network framework in the binary.

**That check is manual.** There is no CI in this repository: what backs the claim
is a Definition of Done item, verified in the code and in the binary on every
task. See [Security](#security).

## Requirements

- macOS 14+ on Apple Silicon. Metal is what makes the latency workable: without
  the GPU the same inference is about 11× slower (a 1635 ms encode against
  143 ms, measured in `docs/pitfalls.md`), which makes dictation unusable.
- Xcode Command Line Tools. **Full Xcode is not required.**
- `cmake`, only to build (`brew install cmake`).
- **The model, 547 MB, which does not ship in the `.app`.** It lives in
  `~/Library/Application Support/NeverType/models/`, and there are two ways to
  put it there. The repository's way is `scripts/setup-bench.sh`, which requires
  **Homebrew** (it installs `whisper-cpp` through it) and **python3** (it creates
  a venv with torch), downloads the **three** bench checkpoints from OpenAI's CDN
  (turbo, medium and small) and converts and quantizes each one. The other way is
  to copy the file from someone who already has it into `models/` and run
  `scripts/fetch-model.sh`, which validates magic and size before installing.
  Both are in [`docs/INSTALL.md`](docs/INSTALL.md).
- **Portuguese speech only.** The language is fixed in the code; there is no
  menu option. See [Limitations](#known-limitations).

whisper.cpp goes into the `.app` statically: to *run*, it depends neither on
Homebrew nor on any installed library. What it needs from outside is the model
above and, on the first launch, the two permissions.

## Installation

```bash
bash scripts/install.sh
```

It builds (if `build/NeverType.app` does not exist yet; after changing code, run
`scripts/build-app.sh` first), installs into `/Applications`, checks the model
and opens the app. The first time takes a few minutes: whisper.cpp is compiled
from source. It does not download the model: if it is missing, it prints the two
paths from [Requirements](#requirements) and carries on.

On the first launch macOS asks for **Microphone** and **Accessibility**. Both are
required: without the microphone there is no audio; without Accessibility the app
does not receive the global key. It warns the way an app without a window can
(the slashed icon, `mic.slash`, "Accessibility: missing" and the item "Open
Accessibility Settings…" in the menu, a line in `nevertype.log`, and macOS's own
prompt), but holding the key does nothing, and whoever does not open the menu
concludes it is broken.

Once the installation is done:

```bash
bash scripts/verify-install.sh
```

### Or ask your agent

There is no prebuilt binary: each installation compiles on its own machine, and
that is what keeps Gatekeeper out of the way. If you use a coding agent, send it
the link to this repository and ask it to follow
[`docs/INSTALL.md`](docs/INSTALL.md), which was written to be executed by an
agent: the order of the steps, what to do on each known failure, what **not** to
try to fix on its own, and the four moments that need you: installing the
Command Line Tools, granting the two permissions, and dictating the sentence that
proves the installation.

## Usage

Hold **Right ⌘**, speak, release. The text appears wherever the cursor is.
Pressing any regular key, or Esc, during the hold cancels and discards the
audio. The key is chosen from the menu: ⌘, ⌥ or ⌃ **on the right side**, and
only those. A modifier on its own types no character and triggers no system
action, which is what spares intercepting the event. Switching keys in the middle
of a hold discards that hold.

**Two taps lock into hands-free**, and the recording continues without the key
held: one tap finishes and transcribes, **Esc** discards. A tap is a hold under
250 ms, and the second one has 300 ms to arrive. While locked, typing does not
cancel: with the key held, a regular key means "this was a shortcut", but in
hands-free there is no modifier held, and a long dictation cannot die because
you typed.

While recording, the menu bar icon turns red and the **floating pill** shows the
microphone level as bars. If they do not move, no sound is coming in, and the
transcription will come back empty. Release the key and it shows a blue wave
while the model works, then goes back to idle when the text comes out. The pill
stays on screen the whole time, even idle: an app without a window that dies
changes nothing visually, and the idle pill is the proof that it is alive. It is
born in the bottom right corner, but it is draggable: drop it near an edge and it
snaps; the position is remembered. And it survives full-screen applications,
where the menu bar is hidden.

A short tone marks start, finish, lock and discard. The one that finishes sounds
lower than the one that starts, and the one that locks goes up, so the direction
tells you what happened without you having to learn which sound is which.

**An empty transcription inserts nothing** and does not enter the history: the
app only writes a line to the log. Without Metal (the app enumerates the ggml
devices at launch) the icon opens slashed and the log warns; without a valid
model, the icon opens slashed and the "Model:" line in the menu carries the
message with the script to run.

**The clipboard is given back.** The text goes in by pasting, so whatever you had
copied comes back right after, images, files and HTML included. If the insertion
cannot happen, the icon stays slashed for 2 s and the text is not lost: it stays
under **Copy Last Transcription**, in the menu bar menu, and in `historico.json`
(see [What stays on disk](#what-stays-on-disk)).

### In the menu bar menu

The first two lines say the current key ("Trigger: Right ⌘ (hold and speak)")
and the hands-free summary. Then:

- **Hotkey**: Right ⌘, ⌥ or ⌃, with a check on the current one. The choice is
  saved and comes back on the next launch.
- **Sounds**: in the same submenu, on by default. A sound that cannot be turned
  off is a defect for anyone working in a shared room. The volume is fixed, with
  no adjustment.
- **Vocabulary…**: opens the vocabulary window: two tabs (**Vocabulary**, for
  the terms, and **Replacements**), plus and minus buttons, saved on every edited
  cell; closing gives the focus back to the app you were in. The counts show up
  in the item itself. What the lists guarantee, and what they do not, is in
  [Limitations](#known-limitations).
- **Microphone**, **Accessibility**: `ok` or `missing`, queried from the system
  every time the menu opens. Without Accessibility, **Open Accessibility
  Settings…** appears as well.
- **Model**, shown as `Metal · load N ms · warm-up N ms`: the backend ggml
  registered, how long the model took to load and how long the warm-up took
  (1 s of silence transcribed at launch). `CPU (SLOW)` in place of `Metal` is a
  failure, and the icon opens slashed to say so. If the model did not load, the
  line carries the error and the script to run.
- **Version**: the commit the binary was built from. It is the real version: the
  one the Finder shows (0.1.0) is fixed.
- **Copy Last Transcription**: appears from the first transcription on; the
  preview is in the tooltip.
- **History**: the last 30, most recent first, with the time and a 44-character
  preview; the submenu appears from the second one on. Clicking copies, the full
  text is in the tooltip, and **Clear History** deletes `historico.json` **and
  `last.wav`**, the audio of the last dictation. They sit in plain text in
  `~/Library/Application Support/NeverType/`: it is a record of what you said,
  and encrypting would keep the key next to the file, on the same machine.
- **Open at Login**: only from the installed copy (`/Applications` or
  `~/Applications`); from anywhere else the app refuses, the icon stays slashed
  for 2 s and the log says to run `install.sh`. Turned off in System Settings,
  the menu says so and offers the shortcut there.
- **Quit NeverType** (⌘Q). Opening the app while it is already open does not
  create a second instance: the new one activates the running one and exits.

## How it works

| | |
|---|---|
| Model | Whisper `large-v3-turbo`, quantized (q5_0), 547 MB |
| Engine | [whisper.cpp](https://github.com/ggml-org/whisper.cpp), statically compiled, Metal backend |
| Model license | MIT, code **and** weights, by OpenAI |
| Capture | `AVAudioEngine`, converted to 16 kHz mono |
| Global key | `NSEvent` in listen mode, without intercepting |
| Insertion | clipboard + synthetic ⌘V |

The model is loaded once at launch and warmed up with 1 s of silence, so each
dictation pays only the inference. It transcribes **Portuguese** only: the
language is fixed in the code.

**Latency barely grows with the length of the sentence.** Five real dictations,
read from the app's log on 2026-08-28: ~614 ms fixed plus ~22 ms per second of
speech (`.vibeflow/backlog.md`, L1). The step is Whisper's 30 s window: from
1.5 s to 19.4 s it cost between 612 and 698 ms; 31 s needed two windows and cost
1299 ms. See [Limitations](#known-limitations).

## Known limitations

**Long dictation costs per 30 s window, and the 1500 ms target was only measured
up to 31 s.** The numbers that circulate in this repository measure different
things:

- **~600 ms** is the app with the model warm: 599 to 609 ms on a short dictation
  (`docs/model-choice.md`) and 612 to 698 ms on four real dictations of 1.5 to
  19.4 s, read from the app's log on 2026-08-28 (`.vibeflow/backlog.md`, L1).
- **~780 ms** is `whisper-cli` on the bench: 782 ms per dictation of up to 30 s,
  by the process's internal stopwatch. It is the number that chose the model,
  and it is not what you feel while dictating.
- **1299 ms** was a 31 s dictation in the app, two windows, in the same
  measurement of 2026-08-28: within the ceiling, although the bench projected
  1640 ms (2 × 820). Above two windows nobody has measured.

There is no warning and no duration limit.

**It transcribes Portuguese only.** The language is fixed in the code (`"pt"`),
with no menu option. English terms in the middle of the speech are the case
measured on the bench; dictating entirely in another language was not measured.

**Bluetooth headsets degrade the audio.** When the microphone opens, macOS puts
Bluetooth headsets into HFP mode at 8 kHz, and cuts the music on top of it. The
conversion works (there is a test), but recognition gets worse. To dictate,
prefer the Mac's microphone.

**The custom vocabulary does not guarantee the term, it only raises the odds.**
The menu has two lists, and they are two on purpose. The **terms** become
whisper's `initial_prompt`: a recognition hint, probabilistic, with no guarantee.
Only the **replacements** are deterministic, and they require you to already know
what the term gets confused with, because they fix "X came out, I wanted Y", and
cannot fix a word that comes out wrong in a different way every time.

**The app may refuse to paste because of another program.** It queries the
macOS *secure input* flag, which exists to protect password typing. The catch is
that the flag is **session-wide**, and does not mean "password field in focus":
any process can turn it on, including in the background, and some apps turn it on
and forget to turn it off. While it is on, NeverType does not paste: it leaves
the text on the clipboard (marked as concealed) and in the menu, the icon stays
slashed for 2 s and the log says what happened. If you are not in a password
field, it was another app.

**A clipboard manager may keep the dictation.** On insertion the text is marked
with `org.nspasteboard.ConcealedType`, which Raycast and Maccy honor; managers
that ignore the mark will record every dictation in their history. The exception
is yours: **"Copy Last Transcription" and the History items copy without the mark
and without giving the clipboard back.** It is a copy you asked for, so the text
stays there and enters the history of any manager.

**Pasting replaces the selection.** Normal paste behavior, but it surprises.

**Moving the app breaks the permission.** It is installed in `/Applications` and
must stay there: the fixed path, together with the stable signature, is what
makes Accessibility survive rebuilds.

## Security

**Nothing leaves the machine at run time.** There is no network API in the app's
code and no network framework in the binary. The project's only download is the
model's, done by hand through the scripts.

### What stays on disk

Everything in `~/Library/Application Support/NeverType/`, in plain text.
Encrypting would keep the key next to the file, on the same machine:

- `historico.json`: the last 30 transcriptions. **Clear History** deletes it.
- `last.wav`: the audio of the last dictation, overwritten on every recording.
  **Clear History** deletes it; cancelling a dictation leaves no file either. The
  transcription does not read from here (it uses the samples in memory); the WAV
  is a debugging artifact.
- `nevertype.log`: diagnostics for the session, truncated on every launch. It
  keeps the time and size of each transcription, **never the text**.
- `vocabulario.json`: the terms and replacements you entered.
- `models/`: the model, 547 MB.

Outside that folder there are only preferences in `UserDefaults` (domain
`com.nevertype.app`): key, sounds and the pill's position, with no text. The
`ultima-transcricao.txt` from earlier versions is deleted at launch.

**The app runs with the hardened runtime**, which turns on library validation:
the process refuses to load code that is not signed along with it. That matters
because NeverType holds Accessibility, the permission to read and inject keys
across the whole system. It is also why whisper.cpp goes in statically: the
validation refuses third-party dylibs.

**The signing certificate is a known and accepted risk.** For the Accessibility
permission to survive rebuilds, the app is signed with a stable local
certificate, and macOS ties Microphone and Accessibility to that certificate.
Consequence: **anyone who already runs code as you on this machine can sign
themselves as NeverType and inherit those permissions.**

This is inherent to a local certificate and was chosen knowingly: the
alternative is ad-hoc signing, which makes macOS revoke the permission on every
build. The mitigations in place reduce the exposure without eliminating the
class:

- the keychain password is derived from the machine's identifier, never
  versioned
- the private key is released only to `codesign`, and to no other application
- the keychain sits in mode 600 and is locked at the end of every build

For distribution beyond personal use, the right thing is an Apple Developer ID.

**Losing the keychain revokes your permission.** It lives in
`~/Library/Keychains/nevertype-signing.keychain-db`. Deleting it makes the next
build generate another certificate, and macOS asks for Accessibility again.

## Development

```bash
bash scripts/build-app.sh     # first time: compiles whisper.cpp into vendor/
swift build && swift test
```

`vendor/` is not versioned. Without it, `swift build` fails with
`could not build Objective-C module 'CWhisper'`, a message that does not say the
cause.

86 tests in **swift-testing**. XCTest is not used: it only exists with full Xcode
installed, and this project builds with the Command Line Tools.

If you are going to touch the code, read [`docs/pitfalls.md`](docs/pitfalls.md)
first. Those are the mistakes this project has already made, with the measured
cost of each; several would slip through code review.

| | |
|---|---|
| `Sources/NeverTypeCore/` | audio conversion, key, transcription, insertion, vocabulary, history, tones and login item: the testable part |
| `Sources/NeverType/` | menu bar app: icon, menu, pill, vocabulary window |
| `scripts/setup-bench.sh` | builds the three ggml models from OpenAI's checkpoints (requires Homebrew and python3) |
| `scripts/fetch-model.sh` | validates and installs the model from `models/` into its final place |
| `scripts/record-fixture.sh` | records bench fixtures in 16 kHz mono (requires `ffmpeg`) |
| `scripts/bench.sh` | measures latency and quality per model |
| `scripts/build-app.sh` | compiles static whisper, assembles and signs |
| `scripts/install.sh` | installs into `/Applications` |
| `scripts/verify-install.sh` | checks app, signature, process and model by bytes |
| `scripts/update.sh` | fetches the remote, rebuilds, reinstalls and verifies |
| `docs/INSTALL.md` | installation guide written for a coding agent to execute |
| `docs/pitfalls.md` | what broke, and why |
| `docs/model-choice.md` | why `large-v3-turbo`, with the numbers |
| `docs/launch-at-login.md` | what opening at login costs, measured |
| `fixtures/README.md` | what to record for the bench, and what not to |

## License

MIT. Depends on [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT) and
on OpenAI's Whisper model (MIT, code and weights).
