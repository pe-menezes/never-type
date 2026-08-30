Português: [README.pt-BR.md](README.pt-BR.md)

# NeverType

Voice dictation that never leaves your machine. Hold a key in any application,
speak, release, and the text appears where the cursor is.

**~600 ms** per dictation, on a MacBook Pro M4 Pro. No network calls.

## Why it exists

Voice dictation tools usually send the audio to a server, and the server makes
them fast. Wherever the content cannot leave the machine, that design rules
them out.

NeverType runs the model on your Mac, from a file on disk, and the audio is
recorded and transcribed there. At run time the app stays off the network.

**That claim is checked by hand.** A Definition of Done item on each spec covers
it, in the sources and in the binary. [Security](#security) gives the source
grep with its terms and its result, and the two commands for the binary side.
The repository has no CI and keeps no record of either check having run.

## Requirements

- macOS 14+ on Apple Silicon. The inference runs on the GPU through Metal, and
  on the CPU the same inference is about 11× slower (a 1635 ms encode against
  143 ms, measured in `docs/pitfalls.md`), which makes dictation unusable.
- Xcode Command Line Tools (`xcode-select --install`), which carry the Swift 6
  toolchain and the macOS SDK the build uses. Full Xcode is optional.
- `cmake`, only to build (`brew install cmake`).
- **The model, 547 MB, which does not ship in the `.app`.** It lives in
  `~/Library/Application Support/NeverType/models/`, and there are two ways to
  put it there. The repository's way is `scripts/setup-bench.sh`, which requires
  **Homebrew** (it installs `whisper-cpp` through it) and **python3** (it creates
  a venv with torch), downloads the **three** bench checkpoints from OpenAI's CDN
  (turbo, medium and small) and converts and quantizes each one. The other way is
  to copy the file from someone who already has it into `models/` and run
  `scripts/fetch-model.sh`, which validates magic and size before installing.
  Both are in [`docs/INSTALL.md`](docs/INSTALL.md). The model is the project's
  only download, and a script you run by hand does it.
- **Portuguese speech only.** The language is `"pt"` in `Transcriber.swift`, and
  changing it means editing that line and rebuilding. See
  [Limitations](#known-limitations).

whisper.cpp is compiled into the `.app` statically ([Security](#security) says
why). Homebrew, cmake and python3 serve the build and the model conversion, and
a running installation uses the model above and, on the first launch, the two
permissions. The installed app runs on macOS's own frameworks plus the
whisper.cpp inside its bundle.

## Installation

```bash
bash scripts/install.sh
```

It builds (if `build/NeverType.app` does not exist yet; after changing code, run
`scripts/build-app.sh` first), installs into `/Applications`, checks the model
and opens the app. The first time takes a few minutes, since whisper.cpp is
compiled from source. The model is a separate step. When it is missing, the
script prints the two paths from [Requirements](#requirements) and carries on.

On the first launch macOS asks for **Microphone** and **Accessibility**, and the
app needs both. The microphone feeds the recording, and Accessibility delivers
the global key. While Accessibility is missing, holding the key does nothing,
and to whoever never opens the menu the app looks broken. It warns the way a
windowless app can, with the slashed icon (`mic.slash`), "Accessibility:
missing" and the item "Open Accessibility Settings…" in the menu, a line in
`nevertype.log`, and macOS's own prompt.

Once the installation is done:

```bash
bash scripts/verify-install.sh
```

### Or ask your agent

The repository ships source only, and each installation compiles on its own
machine, which keeps Gatekeeper out of the way. If you use a coding agent, send
it the link to this repository and ask it to follow
[`docs/INSTALL.md`](docs/INSTALL.md), which was written for an agent to execute.
It gives the order of the steps, what to do on each known failure, a table of
the fixes an agent may apply on its own and the decisions that belong to you,
and the four moments that need you in person: installing the Command Line
Tools, granting Microphone, granting Accessibility, and dictating the sentence
that proves the installation.

## Usage

Hold **Right ⌘**, speak, release, and the text is pasted at the cursor.
Pressing any regular key, or Esc, during the hold cancels and discards the
audio. The menu offers three keys, ⌘, ⌥ and ⌃ **on the right side**, and only
those. A modifier pressed on its own is inert for the application in front and
for the system, and that lets NeverType observe the key in listen mode.
Switching keys in the middle of a hold discards that hold.

**Two taps lock into hands-free**, and the recording continues with the key up.
One tap finishes and transcribes, **Esc** discards, and a regular key leaves the
recording running. The cancel-on-keystroke rule belongs to the hold, where a
regular key means you were pressing a shortcut. In hands-free the modifier is
up, so a keystroke is plain typing and a long dictation survives it. A tap is a
hold under 250 ms, and the second one has 300 ms to arrive.

While recording, the menu bar icon turns red and the **floating pill** shows the
microphone level as bars. If they do not move, no sound is coming in, and the
transcription will come back empty. Release the key and it shows a blue wave
while the model works, then goes back to idle when the text comes out. The pill
stays on screen the whole time, idle included, and serves as a heartbeat, since
a windowless app that dies leaves the screen looking exactly as before. It is
born in the bottom right corner and it is draggable. Drop it near an edge and it
snaps, and the position is remembered. It also survives full-screen
applications, where the menu bar is hidden.

A short tone marks start, finish, lock and discard. The pitch says which one it
was. The finishing tone is lower than the starting one, and the locking tone
goes up.

**An empty transcription is dropped.** The app writes one line to the log and
leaves the history as it was.

**Two launch failures open with the icon slashed.** When the ggml device
enumeration at launch lists no Metal device, the log warns and the "Model:" line
in the menu reads `CPU (SLOW)`. When the model fails to load, the same line
carries the error and the script to run.

**The clipboard is given back.** The text goes in by pasting, and whatever you
had copied comes back 0.6 s later, images, files and HTML included. The app
reads the text back out of the clipboard before it posts the ⌘V, so a paste that
would have landed with your old contents does not happen at all. If the
insertion cannot happen, the app signals it with the **2 s slash**: the icon
shows `mic.slash` for two seconds, then returns to idle, and the log has the
reason. The text stays under **Copy Last Transcription**, in the menu bar menu,
and in `historico.json` (see [What stays on disk](#what-stays-on-disk)).

**The ⌘V only goes out when there is somewhere for it to land.** Before pasting,
the app asks macOS what has the focus. On a button, an open menu or an image, a
⌘V is an arbitrary shortcut in the application in front, so it is not posted,
and you get the 2 s slash with the text on the clipboard and in the menu. The
check answers "paste" whenever it is unsure, which is most of what you dictate
into. [Known limitations](#known-limitations) says how far it reaches and how to
turn it off.

### In the menu bar menu

The first two lines say the current key ("Trigger: Right ⌘ (hold and speak)")
and the hands-free summary. Then:

- **Hotkey**: Right ⌘, ⌥ or ⌃, with a check on the current one. The choice is
  saved and comes back on the next launch.
- **Sounds**: a toggle in the same submenu, on by default, for whoever works in
  a shared room. The volume is fixed.
- **Vocabulary…**: opens the vocabulary window, with two tabs (**Vocabulary**,
  for the terms, and **Replacements**), plus and minus buttons, and a save on
  every edited cell. Closing gives the focus back to the app you were in, and
  the counts show up in the item itself. [Limitations](#known-limitations)
  covers how far each list goes.
- **Microphone**, **Accessibility**: `ok` or `missing`, queried from the system
  every time the menu opens. When Accessibility is missing, **Open
  Accessibility Settings…** appears as well.
- **Model**, shown as `Metal · load N ms · warm-up N ms`: the backend ggml
  registered, how long the model took to load and how long the warm-up took
  (1 s of silence transcribed at launch). `CPU (SLOW)` in place of `Metal` is
  the Metal failure above, and a model that failed to load puts its error on
  this line.
- **Version**: the commit the binary was built from. The Finder shows a fixed
  0.1.0.
- **Copy Last Transcription**: appears from the first transcription on, with
  the preview in the tooltip.
- **History**: the last 30, most recent first, with the time and a 44-character
  preview. The submenu appears from the second one on, clicking copies, and the
  full text is in the tooltip. **Clear History** deletes `historico.json` **and
  `last.wav`**, the audio of the last dictation. Both sit unencrypted in
  `~/Library/Application Support/NeverType/`, a record of what you said, and
  the reason is in [What stays on disk](#what-stays-on-disk).
- **Open at Login**: the app checks its own path when you click, since the
  login item must point at `/Applications` or `~/Applications`. A copy running
  from any other folder is turned down with the 2 s slash and a log line that
  says to run `install.sh`. If you turn it off in System Settings, the menu
  says so and offers a shortcut to that pane.
- **Quit NeverType** (⌘Q). Opening the app while it is already running
  activates the running copy, and the new process exits.

## How it works

| | |
|---|---|
| Model | Whisper `large-v3-turbo`, quantized (q5_0), 547 MB |
| Engine | [whisper.cpp](https://github.com/ggml-org/whisper.cpp), statically compiled, Metal backend |
| Model license | MIT, code **and** weights, by OpenAI |
| Capture | `AVAudioEngine`, converted to 16 kHz mono |
| Global key | `NSEvent` global monitor in listen mode, and the event still reaches the application |
| Insertion | clipboard + synthetic ⌘V, with the focused element checked first |

The model is loaded once at launch and warmed up on one second of silence, and
each dictation then pays the inference alone. Transcription is Portuguese only
([Requirements](#requirements)).

**Latency steps at Whisper's 30 s window rather than growing with the length of
the sentence.** Inside one window the cost stays nearly flat: 599 to 609 ms on a
short dictation, and 612 to 698 ms from 1.5 s to 19.4 s of speech. Crossing into
a second window roughly doubles it, and 31 s cost 1299 ms. Within one window the
numbers fit ~614 ms fixed plus ~22 ms per second of speech. That estimate comes
from five real dictations read off the app's log on 2026-08-28 and written down
in section L1 of `.vibeflow/backlog.md`, a working note and not a reproducible
bench. See [Limitations](#known-limitations).

## Known limitations

**Long dictation costs per 30 s window, and the 1500 ms ceiling
(`docs/model-choice.md`) was measured only up to 31 s.**

| Number | Measures | Source |
|---|---|---|
| **~600 ms** | the app with the model warm. 599 to 609 ms on a short dictation, and 612 to 698 ms on four real dictations of 1.5 to 19.4 s | `docs/model-choice.md`, and the app's log of 2026-08-28 (backlog section L1) |
| **~780 ms** | `whisper-cli` on the bench, 782 ms per dictation of up to 30 s, by the process's internal stopwatch. This number chose the model, and the app's own figure is the row above | `docs/model-choice.md` |
| **1299 ms** | a 31 s dictation in the app, two windows, within the ceiling. The bench had projected 1640 ms (2 × 820) | the same 2026-08-28 log |

Dictations beyond two windows are unmeasured, and the app sets no duration limit
and shows no warning.

**Portuguese only** ([Requirements](#requirements)). The bench covers Portuguese
speech with English terms in the middle of it, and a whole dictation in another
language sits outside that coverage.

**Bluetooth headsets degrade the audio.** When the microphone opens, macOS puts
a Bluetooth headset into narrowband HFP (8 kHz) and cuts the music on top of it.
The conversion up to 16 kHz works (`upsamplesFromBluetoothHandsFreeRate`, in
`Tests/NeverTypeCoreTests/AudioRecorderTests.swift`). Recognition on 8 kHz audio
is worse, and the Mac's own microphone avoids the downgrade.

**The custom vocabulary raises the odds of a term.** The two lists in the menu
do different jobs. The **terms** go into whisper's `initial_prompt`, a
recognition hint the model weighs against the audio, and a listed term can
still come out wrong. The **replacements** are deterministic and fix "X came
out, I wanted Y", so they require you to already know what the term gets
confused with, and a word that comes out wrong in a different way every time
gives them nothing stable to match.

**The app may refuse to paste because of another program.** It queries the
macOS *secure input* flag, which exists to protect password typing. The flag is
**session-wide**. Any process can turn it on, including in the background, and
some apps turn it on and forget to turn it off, so a refusal while you type into
an ordinary text field means some other process holds the flag. While the flag
is on, NeverType skips the ⌘V, leaves the text on the clipboard (marked as
concealed) and in the menu, and signals with the 2 s slash.

**Your clipboard holds the dictation for 0.6 s, and nobody measured that
number.** Applications read the clipboard asynchronously after a ⌘V, so the app
waits before it gives your contents back. Waiting too little pastes what you had
copied before, inside your document. Waiting too long keeps your own clipboard
busy. The number is yours to set, anywhere from 0.1 s to 5 s:

```bash
defaults write com.nevertype.app clipboardRestoreDelay -float 1.2
```

espanso gives the clipboard back after 300 ms and QuiCopy after 100 ms, which
puts 0.6 s at twice the larger of the two. An attempt to replace the timer with
a signal from the system is written up in
`.vibeflow/specs/devolucao-observada-do-pasteboard.md`: it worked, and it broke
pasting in Slack. During those 0.6 s the text sits on the clipboard marked with
`org.nspasteboard.ConcealedType`. Raycast and Maccy honor the mark, and whether
your manager does decides if every dictation ends up in its history. **"Copy
Last Transcription" and the History items copy like a plain ⌘C**, unmarked, and
the clipboard keeps the text, since those are copies you asked for, and any
manager records them.

**The focus check catches controls and gives up on everything else.** Before
pasting, the app asks the Accessibility API what has the focus, and it holds the
⌘V back on a positive answer alone: a button, a checkbox, a slider, an image, a
menu, a menu bar item. A text field, a text area, a combo box, and anything whose
value macOS reports as settable, get the paste. So does everything else: an app
with no Accessibility support, an app that answers with a role nobody listed, a
terminal that draws its own screen, a list or a table where a cell may be
editable. That is deliberate. A check that refuses where you could have typed
leaves you with a dictation you already spoke and an app that did nothing, which
is worse than the blind ⌘V it replaced. To turn it off:

```bash
defaults write com.nevertype.app checkFocusBeforePaste -bool false
```

**Pasting replaces the selection.** If text is selected in the field when the
dictation lands, it goes in over that selection, the same way a ⌘V would.

**Moving the app breaks the permission.** It is installed in `/Applications` and
must stay there. The fixed path and the stable signature ([Security](#security))
together keep Accessibility alive across rebuilds.

## Security

**The app opens no network connection at run time.** On 2026-08-29, `Sources/`
and `Tests/` were grepped for URL loading (`URLSession`, `NSURLSession`,
`NSURLConnection`, `CFNetwork`, `URLRequest`), Network.framework
(`import Network`, `NWConnection`, `NWBrowser`, `NWListener`, `NWPathMonitor`,
`NWEndpoint`), sockets and streams (`socket(`, `connect(`, `getaddrinfo`,
`gethostbyname`, `sockaddr`, `inet_pton`, `CFStream`, `CFSocket`, `CFHost`,
`NSStream`), subprocesses (`Process(`, `posix_spawn`), and `curl`, `wget` and
any `http://` or `https://` literal. None of them hit. The sources import
AVFoundation, AppKit, Carbon.HIToolbox, Foundation, ServiceManagement, `os` and
the bundled CWhisper, `Package.swift` declares no external package, and the
three `Data(contentsOf:)` calls read `vocabulario.json`, `historico.json` and a
test fixture from disk.

**The scripts do download, which is a separate thing.** The same grep over
`scripts/` hits, and it should. `setup-bench.sh` curls the three checkpoints
from OpenAI's CDN and the ggml converter, `build-app.sh` clones whisper.cpp at
its pinned commit, and `update.sh` runs `git fetch` and `git pull`. You run
those by hand, to build or to update, and the model download is the one in
[Requirements](#requirements). The installed app runs none of them.

**The binary side keeps no record.** `Package.swift` links Foundation, Metal,
MetalKit and Accelerate plus six static whisper and ggml archives, and names no
network framework, which is the build recipe and not the built file. On an
installed copy, `otool -L` on
`/Applications/NeverType.app/Contents/MacOS/NeverType` lists the libraries it
links, and `nm -u` on the same path lists the symbols it leaves undefined. The
grep above does not reach the whisper.cpp compiled into those archives either.
Nobody ran either command for this text, and what the claim rests on there is
the hand-run Definition of Done item from [Why it exists](#why-it-exists).

### What stays on disk

Everything in `~/Library/Application Support/NeverType/` is unencrypted.
Encrypting it would put the key on the same machine, next to the file, within
reach of anyone who can already read the file.

- `historico.json` holds the last 30 transcriptions.
- `last.wav` is the last dictation's audio, overwritten on every recording.
  Cancelling a dictation leaves no file. The transcription runs on the samples
  in memory, and the WAV is a debugging artifact.
- `nevertype.log` holds the session's diagnostics and is truncated on every
  launch. It keeps the time and size of each transcription.
- `vocabulario.json` holds the terms and replacements you entered.
- `models/` holds the model, 547 MB.

**Clear History** deletes `historico.json` and `last.wav`, the two files that
hold what you said.

Outside that folder, `UserDefaults` (domain `com.nevertype.app`) holds five
preferences: the key, the sounds toggle, the pill's position,
`clipboardRestoreDelay` and `checkFocusBeforePaste`. None of them holds text.
The last two have no menu item, and the log line written at launch
(`insertion: …`) prints the values in effect. The `ultima-transcricao.txt` from
earlier versions is deleted at launch.

**The app runs with the hardened runtime**, which turns on library validation.
The process then refuses to load code that is not signed along with it.
NeverType holds Accessibility, the permission to read and inject keys across the
whole system, and library validation keeps foreign code out of a process with
that power. The validation also refuses third-party dylibs, which forces
whisper.cpp to be compiled in statically.

**The signing certificate is a known and accepted risk.** For the Accessibility
permission to survive rebuilds, the app is signed with a stable local
certificate, and macOS ties Microphone and Accessibility to that certificate.
**Anyone who already runs code as you on this machine can sign themselves as
NeverType and inherit those permissions.**

A local certificate carries that risk by nature, and the choice was made
knowingly. The alternative, ad-hoc signing, makes macOS revoke the permission on
every build. The mitigations in place narrow the exposure to that attack:

- the keychain password is derived from the machine's identifier and stays out
  of the repository
- the private key is released to `codesign` alone
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

106 tests in **swift-testing**, which ships with the Command Line Tools. XCTest
ships with full Xcode alone.

[`docs/pitfalls.md`](docs/pitfalls.md) lists the 24 things that broke in this
project, several of which would pass code review, with the measured cost of
each.

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
| `fixtures/README.md` | how to record the bench fixtures, and the three clips it asks for |

## License

MIT. Depends on [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT) and
on OpenAI's Whisper model (MIT, code and weights).
