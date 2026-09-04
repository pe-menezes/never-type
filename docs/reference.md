# NeverType reference

What the app does once it is installed, item by item. The `README.md` covers
what it is, what it requires and how to install it.

## Recording

- Hold the key, speak, release. Any regular key, or Esc, pressed during the hold
  cancels and discards the audio.
- The key is any modifier on either side, Fn, or a mouse button from the third
  on. A modifier pressed on its own is inert for the application in front and
  for the system, which lets NeverType observe it in listen mode without
  intercepting the event. A mouse button is listened to the same way, and its
  click still reaches the app in front: in a browser, button 4 is Back. A
  button remapped by the mouse software never reaches NeverType, and neither
  does Fn on a keyboard that handles it in firmware. The menu keeps three quick
  picks, Right ⌘, ⌥ and ⌃, and the rest is chosen by pressing it, in the panel
  described under [Choosing the key](#choosing-the-key).
- Switching keys in the middle of a hold discards that hold.
- Two taps lock into hands-free, and the recording continues with the key up.
  One tap finishes and transcribes, Esc discards, and a regular key leaves the
  recording running. A keystroke cancels only while the modifier is down, where
  it means you were pressing a shortcut. A tap is a hold under 250 ms, and the
  second one has 300 ms to arrive.
- Hands-free can be turned off, in its own item in the menu. Off, two taps no
  longer lock: the key records while it is held, the release finishes it, and a
  tap under 250 ms concludes on the release, with no 300 ms wait for a second
  one. Switching it while a recording is running discards that
  recording, because the gesture holding it open goes with the switch. The same
  happens if you change the key mid-recording.
- A second key can lock hands-free with one tap. **Choose a hands-free key…**,
  in the Hands-free submenu, opens the same panel for it: one tap locks the
  recording, the next tap finishes and transcribes, Esc discards, and the
  trigger's own tap finishes as well. The tap also works while the trigger is
  still held: hold Right ⌥, speak, tap Right ⌘, and the recording is locked
  without a release and without a second tap. That is the chord this app can
  offer. A chord with a regular key, ⌘ Space or ⌥ Space, would reach the app
  in front (Spotlight, Raycast, Alfred, a non-breaking space), since the app
  listens without intercepting. The panel refuses the trigger for that
  role (`That is the push-to-talk key. Pick another one for hands-free.`), and
  picking the hands-free key as the trigger from the quick picks removes it,
  with `hands-free key removed: it is now the trigger` in the log. The choice
  is saved and comes back on the next launch. With hands-free off, the second
  key does nothing and its items leave the submenu. The choice stays saved and
  waits for the mode to come back.
- An empty transcription is dropped. The app writes one line to the log and
  leaves the history as it was.
- Bluetooth headsets go into narrowband HFP (8 kHz) when the microphone opens,
  and macOS cuts the music on top of it. The conversion up to 16 kHz works
  (`upsamplesFromBluetoothHandsFreeRate`, in
  `Tests/NeverTypeCoreTests/AudioRecorderTests.swift`). Recognition on 8 kHz
  audio is worse, and the Mac's own microphone avoids the downgrade.

### Choosing the key

**Other key or mouse button…**, in the Hotkey submenu, opens a panel titled
`Choose the trigger`. It says `Press the key or mouse button to hold while you
dictate.` and, under that, `A modifier key on either side, Fn, or a mouse
button from the third on. Esc closes.` The next press decides:

| Answer | Keys | What the panel says |
|---|---|---|
| Accepted | Right ⌘, Right ⌥, Right ⌃, Left ⌃, a mouse button from the third on | |
| Accepted with a caveat | Fn | Fn also opens the emoji picker unless System Settings > Keyboard sets "Press 🌐 key to" to "Do Nothing". Some keyboards handle Fn on their own, and macOS never sees it. |
| Accepted with a caveat | Left ⌥ | On a US layout, Left ⌥ types the accents, and every accent would start a recording. |
| Accepted with a caveat | A mouse button | The click still reaches the app in front: in a browser, button 4 is Back. A button remapped by the mouse software never reaches NeverType. |
| Refused | A regular key, or a combination | One key on its own. A regular key or a combination would also reach the app in front. |
| Refused | ⇧, either side | Not ⇧: every capital letter would start a recording. |
| Refused | Left ⌘ | Not Left ⌘: every shortcut would start a recording. Right ⌘ works. |
| Refused | Caps Lock | Not Caps Lock: it toggles the keyboard state and cannot be held. |
| Refused | The primary or secondary click | Not the primary or secondary click. A mouse button from the third on works. |

A modifier is accepted on its release, and only if nothing else was pressed in
between: a combination is refused. An accepted key closes the panel and takes
effect at once. A caveat waits for the **Use <key>** button (Return confirms)
before the key counts. A refusal leaves the panel waiting for the next press.
Esc closes it with nothing changed. Five seconds with no press at all show
`Nothing arrived. Some keyboards handle Fn on their own, and a button remapped
by the mouse software never reaches NeverType. Esc closes.` While the panel is
open the current key does not record: the log says `capture panel open:
trigger monitor off`, and `capture panel closed: trigger monitor back on` on
the way out. Closing the panel gives the focus back to the app you were in.

The refused keys are refused because of what a false start costs: pressing the
trigger switches the microphone on, plays the start tone and shows the pill,
and the cancel plays the discard tone. A key that is part of typing or of
everyday shortcuts would do all of that on each of them.

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

Clicking it opens the same menu the menu bar icon opens, next to the orb. The
two gestures share one button, and 3 px of travel separate them: under that it
is a click, and from there on the orb follows the pointer and no menu opens. The
cursor is the ordinary arrow, and it turns into a closed hand once the orb is
really moving. Near an edge of the screen, which is where the orb tends to live,
macOS flips the menu to whichever side fits. While the menu is open the orb
drops below it, so a menu that lands on top of the orb covers it.

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

## The tooltip

Rest the pointer on the menu bar icon, or on the orb, and after a moment it
says `NeverType. Hold Right ⌘ to dictate. Click for the menu.`, naming whichever
key is chosen. It is the only thing the app says without being clicked, and it
exists because reading the menu means having already worked out that there is a
menu to open.

On the icon this is the ordinary menu bar behavior. On the orb it is a tooltip
inside a borderless panel that never becomes the active window, which needed the
panel to accept mouse-moved events and the view to keep tracking marked
`.activeAlways`. Whether macOS draws it there was not watched happening. The app
was built, installed and exercised by hand on 2026-09-01, and in that pass nobody
rested the pointer on the orb to look.

## The menu bar menu

It opens from two places, the menu bar icon and a click on the orb, and it is
rebuilt from scratch every time, so it never shows stale state. In full screen
the orb is the only one of the two that exists.

```
Hotkey: Right ⌘            >
Hands-free: double tap     >
Vocabulary…
──────────────
Copy Last Transcription
History (30)               >
──────────────
Start NeverType with macOS
Quit NeverType             ⌘Q
```

- **Hotkey: Right ⌘**: the title carries the key in use, so the line teaches the
  gesture to somebody who opened the menu for something else. The submenu offers
  Right ⌘, ⌥ and ⌃ as quick picks, with a check on the current one. A key
  chosen through the panel that is not one of the three shows up as a fourth
  line, checked. Under a separator, **Other key or mouse button…** opens the
  panel described in [Choosing the key](#choosing-the-key). The choice is
  saved and comes back on the next launch.
- **Sounds**: a toggle in the same submenu, on by default, for whoever works in
  a shared room. The volume is fixed.
- **Hands-free: double tap**: the submenu holds the switch, on by default, and
  three lines of instruction under it: `Double-tap Right ⌘ to lock`, `Tap once
  to finish · Esc discards`, `Typing does not cancel while locked`. Under a
  separator comes the second key. While none is chosen, the item is **Choose a
  hands-free key…**. With one chosen, the submenu shows the line `Tap Right ⌥
  to lock, tap again to finish`, then **Change hands-free key…** and **Remove
  hands-free key**, and the title reads **Hands-free: double tap or Right ⌥**,
  so both ways in are taught from the menu itself. Turned off, the item reads
  **Hands-free: off** and the submenu keeps one
  line, `Right ⌘ only records while held`. The second key stays saved and does
  nothing until the mode is on again. The choice is saved. This is the way out
  for somebody who locked by accident: turning it off ends the recording that
  was running.
- **Vocabulary…**: opens the vocabulary window, with two tabs (**Vocabulary**,
  for the terms, and **Replacements**), plus and minus buttons, and a save on
  every edited cell. Closing gives the focus back to the app you were in, and
  the counts show up in the item itself.
- **Copy Last Transcription**: appears from the first transcription on, with the
  preview in the tooltip.
- **History**: the last 30, most recent first, with the time and a 44-character
  preview. The submenu appears from the second one on, clicking copies, and the
  full text is in the tooltip. **Clear History** deletes `historico.json` and
  `last.wav`.
- **Start NeverType with macOS**: the app checks its own path when you click,
  since the login item must point at `/Applications` or `~/Applications`. A copy
  running from
  any other folder is turned down with the two-second slash and a log line that
  says to run `install.sh`. If you turn it off in System Settings, the menu says
  so and offers a shortcut to that pane. What it costs at boot is measured in
  [`launch-at-login.md`](launch-at-login.md).
- **Quit NeverType** (⌘Q). Opening the app while it is already running activates
  the running copy, and the new process exits.

### The lines that only show up when they are needed

- **Accessibility: missing** and **Microphone: missing**, queried from the system
  every time the menu opens. Granted, they take no line at all. Missing, they
  open the menu, above everything else, and **Open Accessibility Settings…**
  comes right under the Accessibility one. The microphone has no item of its
  own: macOS asks for it once, at the first launch.
- **turned off in Login Items**, with **Open Login Items…** under it, when the
  login item is registered and you turned it off in System Settings.

### Diagnostics, under Option

Hold Option as you open the menu, from the icon or from the orb, and the
diagnostic lines come back:

- **Trigger: Right ⌘ (hold and speak)** opens the menu, and under it the summary
  `double-tap locks · tap to finish · Esc discards`. The summary describes the
  double tap, so it only shows while hands-free is on. With hands-free off, hold
  and speak is the whole cycle and the line above it already says it.
- **Model**, in a block of its own above the login item, shown as
  `Metal · load N ms · warm-up N ms`: the backend ggml
  registered, how long the model took to load and how long the warm-up took
  (1 s of silence transcribed at launch). `CPU (SLOW)` in place of `Metal` is
  the Metal failure below, and a model that failed to load puts its error on
  this line, with the script to run.
- **Version**: the commit the binary was built from. The Finder shows a fixed
  0.1.0.

The key is read once, at the moment the menu is built. Holding Option after the
menu is already on screen changes nothing: close it and open it again with the
key down.

Two launch failures open with the icon slashed. The ggml device enumeration at
launch may list no Metal device, and the model may fail to load. Both say so in
the log, and on the "Model:" line under Option.

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

Outside that folder, `UserDefaults` holds six preferences: the key, hands-free,
the sounds toggle, the pill's position, `clipboardRestoreDelay` and
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
| Global key | `NSEvent` global monitor in listen mode, for the modifier keys and the extra mouse buttons alike, and the event still reaches the application |
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
