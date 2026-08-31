# NeverType reference

What the app does once it is installed, item by item. The `README.md` covers
what it is, what it requires and how to install it.

## Recording

- Hold the key, speak, release. Any regular key, or Esc, pressed during the hold
  cancels and discards the audio.
- The menu offers three keys, ⌘, ⌥ and ⌃ on the right side, and only those. A
  modifier pressed on its own is inert for the application in front and for the
  system, which lets NeverType observe the key in listen mode without
  intercepting the event.
- Switching keys in the middle of a hold discards that hold.
- Two taps lock into hands-free, and the recording continues with the key up.
  One tap finishes and transcribes, Esc discards, and a regular key leaves the
  recording running. A keystroke cancels only while the modifier is down, where
  it means you were pressing a shortcut. A tap is a hold under 250 ms, and the
  second one has 300 ms to arrive.
- An empty transcription is dropped. The app writes one line to the log and
  leaves the history as it was.
- Bluetooth headsets go into narrowband HFP (8 kHz) when the microphone opens,
  and macOS cuts the music on top of it. The conversion up to 16 kHz works
  (`upsamplesFromBluetoothHandsFreeRate`, in
  `Tests/NeverTypeCoreTests/AudioRecorderTests.swift`). Recognition on 8 kHz
  audio is worse, and the Mac's own microphone avoids the downgrade.

## The floating pill

The overlay remains a 34 px orb across all four states. At rest it shows the
NeverType mark. During recording, including hands-free, the mark's same three
bars become a live waveform without changing thickness or position. Bars that
do not move mean no sound is coming in, and the transcription will come back
empty. After the release, the bars collapse into three moving dots in place and
the mark's cursor stays unchanged while the model works. The menu bar uses the
same identity.

The pill stays on screen the whole time, idle included, and serves as a
heartbeat, since a windowless app that dies leaves the screen looking exactly as
before. It is born in the bottom right corner and it is draggable. Drop it near
an edge and it snaps, and the position is remembered. It also survives
full-screen applications, where the menu bar is hidden.

A short tone marks start, finish, lock and discard, and the pitch says which one
it was. The finishing tone is lower than the starting one, and the locking tone
goes up.

## Insertion

The text goes in by pasting. Before posting the ⌘V, the app reads the text back
out of the clipboard, so a paste that would have landed with your old contents
does not happen at all. Whatever you had copied comes back 0.6 s later, images,
files and HTML included.

The app holds the paste back when the focused element takes no text, and when
macOS secure input is on:

- **The focused element.** The app asks the Accessibility API what has the
  focus, and it holds the ⌘V back on a positive answer alone: a button, a
  checkbox, a slider, an image, a menu, a menu bar item. A text field, a text
  area, a combo box, and anything whose value macOS reports as settable, get the
  paste. So does everything else: an app with no Accessibility support, an app
  that answers with a role nobody listed, a terminal that draws its own screen,
  a list or a table where a cell may be editable. The reasoning is in
  [`pitfalls.md`](pitfalls.md).
- **Secure input.** The macOS flag of that name exists to protect password
  typing, and it is session-wide. Any process can turn it on, including in the
  background, and some apps turn it on and forget to turn it off. A refusal
  while you type into an ordinary text field means some other process holds the
  flag. The app then leaves the text on the clipboard, marked as concealed, and
  in the menu.

Whenever the insertion cannot happen, the menu bar shows the NeverType mark
with a slash for two seconds and then returns to idle, and the log has the
reason. The text stays under **Copy Last Transcription** in the menu and in
`historico.json`.

Pasting replaces the selection, the same way a ⌘V would.

## Settings with no menu item

Both live in `UserDefaults`, domain `com.nevertype.app`, and the log line
written at launch (`insertion: …`) prints the values in effect.

```bash
defaults write com.nevertype.app clipboardRestoreDelay -float 1.2   # 0.1 s to 5 s, default 0.6
defaults write com.nevertype.app checkFocusBeforePaste -bool false  # default true
```

The 0.6 s came from what other tools do, and nobody here measured it.
[`pitfalls.md`](pitfalls.md) tells that story, including the attempt to replace
the timer with a signal from the system. During those 0.6 s the text carries
`org.nspasteboard.ConcealedType`. Raycast and Maccy honor the mark, and a
manager that ignores it records every dictation in its history. "Copy Last
Transcription" and the History items copy like a plain ⌘C, unmarked, and the
clipboard keeps the text, since those are copies you asked for.

## Custom vocabulary

The terms go into whisper's `initial_prompt`, a recognition hint the model
weighs against the audio, and a listed term can still come out wrong.

The replacements run over the finished text and are deterministic. They fix "X
came out, I wanted Y", so they require you to already know what the term gets
confused with. A word that comes out wrong in a different way every time gives
them nothing stable to match.

## The menu bar menu

The first two lines say the current key ("Trigger: Right ⌘ (hold and speak)")
and the hands-free summary. Then:

- **Hotkey**: Right ⌘, ⌥ or ⌃, with a check on the current one. The choice is
  saved and comes back on the next launch.
- **Sounds**: a toggle in the same submenu, on by default, for whoever works in
  a shared room. The volume is fixed.
- **Vocabulary…**: opens the vocabulary window, with two tabs (**Vocabulary**,
  for the terms, and **Replacements**), plus and minus buttons, and a save on
  every edited cell. Closing gives the focus back to the app you were in, and
  the counts show up in the item itself.
- **Microphone**, **Accessibility**: `ok` or `missing`, queried from the system
  every time the menu opens. When Accessibility is missing, **Open
  Accessibility Settings…** appears as well.
- **Model**, shown as `Metal · load N ms · warm-up N ms`: the backend ggml
  registered, how long the model took to load and how long the warm-up took
  (1 s of silence transcribed at launch). `CPU (SLOW)` in place of `Metal` is
  the Metal failure below, and a model that failed to load puts its error on
  this line, with the script to run.
- **Version**: the commit the binary was built from. The Finder shows a fixed
  0.1.0.
- **Copy Last Transcription**: appears from the first transcription on, with the
  preview in the tooltip.
- **History**: the last 30, most recent first, with the time and a 44-character
  preview. The submenu appears from the second one on, clicking copies, and the
  full text is in the tooltip. **Clear History** deletes `historico.json` and
  `last.wav`.
- **Open at Login**: the app checks its own path when you click, since the login
  item must point at `/Applications` or `~/Applications`. A copy running from
  any other folder is turned down with the two-second slash and a log line that
  says to run `install.sh`. If you turn it off in System Settings, the menu says
  so and offers a shortcut to that pane. What it costs at boot is measured in
  [`launch-at-login.md`](launch-at-login.md).
- **Quit NeverType** (⌘Q). Opening the app while it is already running activates
  the running copy, and the new process exits.

Two launch failures open with the icon slashed. The ggml device enumeration at
launch may list no Metal device, and the model may fail to load. Both say so in
the log and on the "Model:" line.

## What stays on disk

Everything in `~/Library/Application Support/NeverType/` is unencrypted.
Encrypting it would put the key on the same machine, next to the file, within
reach of anyone who can already read the file.

| | |
|---|---|
| `historico.json` | the last 30 transcriptions |
| `last.wav` | the last dictation's audio, overwritten on every recording. Cancelling a dictation leaves no file. The transcription runs on the samples in memory, and the WAV is a debugging artifact |
| `nevertype.log` | the session's diagnostics, truncated on every launch. It keeps the time and size of each transcription, never the text |
| `vocabulario.json` | the terms and replacements you entered |
| `models/` | the model, 547 MB |

**Clear History** deletes `historico.json` and `last.wav`, the two files that
hold what you said.

Outside that folder, `UserDefaults` holds five preferences: the key, the sounds
toggle, the pill's position, `clipboardRestoreDelay` and
`checkFocusBeforePaste`. None of them holds text. The `ultima-transcricao.txt`
from earlier versions is deleted at launch.

## The check behind "no network at run time"

On 2026-08-29, `Sources/` and `Tests/` were grepped for URL loading
(`URLSession`, `NSURLSession`, `NSURLConnection`, `CFNetwork`, `URLRequest`),
Network.framework (`import Network`, `NWConnection`, `NWBrowser`, `NWListener`,
`NWPathMonitor`, `NWEndpoint`), sockets and streams (`socket(`, `connect(`,
`getaddrinfo`, `gethostbyname`, `sockaddr`, `inet_pton`, `CFStream`, `CFSocket`,
`CFHost`, `NSStream`), subprocesses (`Process(`, `posix_spawn`), and `curl`,
`wget` and any `http://` or `https://` literal. None of them hit. The sources
import AVFoundation, AppKit, Carbon.HIToolbox, Foundation, ServiceManagement,
`os` and the bundled CWhisper, `Package.swift` declares no external package, and
the three `Data(contentsOf:)` calls read `vocabulario.json`, `historico.json`
and a test fixture from disk.

A Definition of Done item on each spec covers the claim, in the sources and in
the binary. The repository has no CI and keeps no record of either check having
run.

The scripts do download, which is a separate thing. `setup-bench.sh` curls the
three checkpoints from OpenAI's CDN and the ggml converter, `build-app.sh`
clones whisper.cpp at its pinned commit, and `update.sh` runs `git fetch` and
`git pull`. You run those by hand, to build or to update, and the model is the
project's only download. The installed app runs none of them.

The binary side keeps no record. `Package.swift` links Foundation, Metal,
MetalKit and Accelerate plus six static whisper and ggml archives, and names no
network framework, which is the build recipe and not the built file. On an
installed copy, `otool -L` on
`/Applications/NeverType.app/Contents/MacOS/NeverType` lists the libraries it
links, and `nm -u` on the same path lists the symbols it leaves undefined. The
grep above does not reach the whisper.cpp compiled into those archives either.
Nobody ran either command for this text.

## Signing, and what it costs

The app runs with the hardened runtime, which turns on library validation. The
process then refuses to load code that is not signed along with it. NeverType
holds Accessibility, the permission to read and inject keys across the whole
system, and library validation keeps foreign code out of a process with that
power. The validation also refuses third-party dylibs, which forces whisper.cpp
to be compiled in statically ([`pitfalls.md`](pitfalls.md)).

For the Accessibility permission to survive rebuilds, the app is signed with a
stable local certificate, and macOS ties Microphone and Accessibility to that
certificate. **Anyone who already runs code as you on this machine can sign
themselves as NeverType and inherit those permissions.** A local certificate
carries that risk by nature, and the choice was made knowingly. The alternative,
ad-hoc signing, makes macOS revoke the permission on every build. The mitigations
in place narrow the exposure to that attack:

- the keychain password is derived from the machine's identifier and stays out
  of the repository
- the private key is released to `codesign` alone
- the keychain sits in mode 600 and is locked at the end of every build

For distribution beyond personal use, the right thing is an Apple Developer ID.

The keychain lives in `~/Library/Keychains/nevertype-signing.keychain-db`.
Deleting it makes the next build generate another certificate, and macOS asks
for Accessibility again. The app is installed in `/Applications` and has to stay
there: the fixed path and the stable signature together keep Accessibility alive
across rebuilds.

## How it works

| | |
|---|---|
| Model | Whisper `large-v3-turbo`, quantized (q5_0), 547 MB. Loaded once at launch and warmed up on one second of silence, so each dictation pays the inference alone |
| Engine | [whisper.cpp](https://github.com/ggml-org/whisper.cpp), statically compiled, Metal backend |
| Capture | `AVAudioEngine`, converted to 16 kHz mono |
| Global key | `NSEvent` global monitor in listen mode, and the event still reaches the application |
| Insertion | clipboard + synthetic ⌘V, with the focused element checked first |
| Language | `"pt"`, fixed in `Transcriber.swift`. Another language means editing that line and rebuilding |

Homebrew, cmake and python3 serve the build and the model conversion. The
installed app runs on macOS's own frameworks plus the whisper.cpp inside its
bundle, and what it needs from outside is the model and, on the first launch,
the two permissions.

## The repository

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
| [`INSTALL.md`](INSTALL.md) | installation guide written for a coding agent to execute |
| [`pitfalls.md`](pitfalls.md) | what broke, and why |
| [`model-choice.md`](model-choice.md) | why `large-v3-turbo`, with the numbers |
| [`launch-at-login.md`](launch-at-login.md) | what opening at login costs, measured |
| `fixtures/README.md` | how to record the bench fixtures, and the three clips it asks for |
