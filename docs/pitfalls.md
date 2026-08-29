# Pitfalls

What broke in this project, and the measured cost of each mistake. Almost none
of these showed up in code review: most only appeared when running, and several
had the program **reporting that everything was fine** while it was not.

They are here because none of them is specific to this app.

---

## Verification that lets itself be fooled

### Searching a log for a word does not prove anything happened

`ggml` initializes the Metal device just to enumerate it, even when inference
runs on the CPU. A log from `whisper-cli -ng` (explicit CPU) contains **37
lines** with the word "metal", including `using embedded metal library`.

A `grep -qi metal` accepted a CPU run as proof of GPU. Cost, measured on the
same model and audio: **a 1635 ms encode on CPU against 143 ms on Metal**. The
whole bench was reporting CPU numbers as if they were the app's.

The real discriminator is the backend that was chosen, and the guard requires the
positive **and** rejects the negative:

```bash
metal_is_active() {
  local log="$1"
  grep -q 'whisper_backend_init_gpu: no GPU found' "$log" && return 1
  grep -Eq 'whisper_backend_init_gpu:.*MTL' "$log"
}
```

Inside the process, the correct version does not even look at a log: it
enumerates `ggml_backend_dev_count()` and reads `ggml_backend_dev_name()`.

**Rule:** logs contain the vocabulary of things that did **not** happen.

### A magic number is not compared as text

The ggml magic is `0x67676d6c`, written as a little-endian uint32. The bytes on
disk come out reversed: `6c 6d 67 67`, which read as text is **`lmgg`**, not
`ggml`.

`head -c 4 file` = `"ggml"` rejected **every valid model**, including the
reference one distributed by Homebrew. Compare in hexadecimal.

### The magic alone does not validate a file

An interrupted download has the right first bytes. Worse, whisper.cpp accepts a
truncated model as an "empty model for testing" and returns a **valid**
context. The first inference kills the process with `std::out_of_range`, a C++
exception that no Swift `try` intercepts.

Reproduced: 100 KB of the real model on the production path → `exit 134`, no
warning, no icon, no menu. The app simply did not open.

**Rule:** magic **and** a size floor proportional to the real artifact. A 50 MB
floor for a 547 MB model approves a truncated download.

And a written rule is not an applied rule: until 2026-08-29 this paragraph
already existed and the floor was 50 MB in three of the five places that
validate the model (`ModelStore.minimumBytes` in the app, `fetch-model.sh` and
`setup-bench.sh`); only `install.sh` and `verify-install.sh` used 400. Today it is
400 MB in all five, and on the bench the floor is per model (130 MB for the
181 MB `small`). Cost of checking: one `grep` for the number.

---

## Concurrency the compiler does not see

### A closure inside a `@MainActor` method inherits the isolation

This one took the app down twice, and the first fix did not work.

The `AVCaptureDevice.requestAccess` callback arrives on a background queue.
Using `MainActor.assumeIsolated` there is asserting something false, and Swift
checks it at runtime: `EXC_BREAKPOINT` in `_swift_task_checkIsolatedSwift`.

The obvious fix (swapping the body for `Task { @MainActor in }`) **does not
solve it**. Closures written inside a `@MainActor` method inherit that isolation
by inference, and the check trips in the **outer** closure, before reaching the
body.

The way out was the async API, which has no closure:

```swift
Task { @MainActor in
    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    self.render(granted ? .idle : .blocked)
}
```

**Cruel detail:** the path only runs when the permission is *undetermined*. In
any test with the permission already granted, the bug does not appear.

### `AVAudioNodeTapBlock` is not `Sendable`, and the build comes out clean

The audio tap runs on a real-time thread; `stop()` runs on main. Both touched the
same `AVAudioFile` and the same converter with no synchronization. Swift 6 with
strict concurrency **does not complain**, because the block's type is not
marked.

The fix: the tap only copies the buffer and dispatches to a serial queue that
owns the state; `stop()` uses `queue.sync` as a barrier. `removeTap` does not
guarantee the absence of a callback in flight.

### The SDK annotates `@Sendable` underneath the code, and the build breaks with nobody touching it

The opposite of the previous item: here the compiler started seeing **more**, on
another machine, in code that did not change.

`Resampler.convert(_:)` handed the converter a block that captured a `var`
(`supplied`) and the input `AVAudioPCMBuffer`. It compiled on the machine where
the project was born, with Command Line Tools only. The compiler version there
**was not recorded**, which is half of this pitfall. On a clean clone of
the same commit (`0d7efbe`), with Apple Swift 6.2.3 (swiftlang-6.2.3.3.21), full
Xcode and SDK MacOSX26.2, `swift build --build-tests` and `swift test` exit with
1 and three errors, measured on 2026-08-29:

```
AudioRecorder.swift:90:20: error: capture of 'input' with non-Sendable type 'AVAudioPCMBuffer' in a '@Sendable' closure
AudioRecorder.swift:84:16: error: reference to captured var 'supplied' in concurrently-executing code
AudioRecorder.swift:88:13: error: mutation of captured var 'supplied' in concurrently-executing code
```

The last line of the output is `error: fatalError`, which says nothing. The
cause is above. And it is the block's type. Read in the header,
`AVFAudio.framework/Headers/AVAudioConverter.h`, line 154 (the same line in the
Command Line Tools' `MacOSX26.2.sdk` and in Xcode 26.2's `MacOSX.sdk`):

```objc
typedef AVAudioBuffer * __nullable (^ NS_SWIFT_SENDABLE AVAudioConverterInputBlock)(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus* outStatus);
```

The `NS_SWIFT_SENDABLE` is in `MacOSX26.sdk` (26.0) and in 26.2, and **is not in
`MacOSX15.4.sdk`**: `grep -c "NS_SWIFT_SENDABLE AVAudioConverterInputBlock"`
gives 0 there. The annotation came in with SDK 26.0, and Apple's public
documentation still shows the `typealias` without it: the docs are not the SDK.
In Swift 6 with strict concurrency, every type Apple starts marking becomes an
error in code nobody touched.

The origin machine measured macOS 26.2 on 2026-08-28 and compiled. The only
explanation consistent with the facts is that the Command Line Tools there have
a 15.x SDK, not updated. That is inference, not measurement: nobody checked
there, and the compiler version there is still unknown.

The fix: the buffer sits in an `OSAllocatedUnfairLock<AVAudioPCMBuffer?>`
(`Sendable`, macOS 13+), which the block empties on the first call and answers
`.noDataNow` afterwards. No `@preconcurrency import`, no looser
`-strict-concurrency`, no `@unchecked Sendable`: each of those erases the
diagnostic instead of handling the case, and an honest red is worth more than a
green obtained by loosening the ruler. On which thread the converter calls the
block Apple does not document (only that the parameter is non-escaping); the
lock costs nanoseconds and makes the answer unnecessary.

Afterwards, measured on 2026-08-29 on the same machine and the same tree:
`swift build --build-tests` exits 0, **0 errors, 6 warnings (the same 6 as the
broken round, none new)**; `swift test --disable-xctest
--enable-swift-testing` exits 0, **81 of 81 tests in 12 suites**, 1.507 s.

**Rule:** "it compiles here" without `swift --version` and
`xcrun --show-sdk-version` written down is not reproducible. Record both along
with the measurement. Apple moves the `Sendable` ruler with every SDK.

### Query-then-decide is not mutual exclusion

`NSRunningApplication.runningApplications(withBundleIdentifier:)` to guarantee a
single instance fails on simultaneous launches: it is two steps, and the
LaunchServices registration is asynchronous. **3 out of 3** attempts ended with
two instances.

With two global key monitors, one dictation becomes two recordings, two
transcriptions and two ⌘V. `flock` solves it in one indivisible step.

---

## Audio

### The converter holds back samples, and the end of the speech disappears

`AVAudioConverter` keeps samples inside the resampling filter between calls.
During the recording that does not matter: the residue comes out on the next
call. At the end, it matters: **982 frames held back in 1 s of audio at
48 kHz**, which is 61 ms. That is exactly where the end of the sentence is.

Without draining, the last word of every dictation vanished.

### One call does not drain the converter

The converter fills up to the capacity of the output buffer and keeps the rest.
Assuming one call is enough worked for downsampling and truncated on upsampling:
**3744 frames lost** converting 8 kHz (a Bluetooth headset in HFP mode) to
16 kHz. It has to be pumped until dry.

### A stopped audio engine still holds the microphone

An `AVAudioEngine` that is stopped but alive keeps the input node configured, and
macOS keeps counting the app as a microphone user. The system indicator stays
lit the whole time. The instance has to be born and die with each use, including
on the error path:

```swift
var started = false
defer { if !started { self.engine?.reset(); self.engine = nil } }
```

---

## macOS: things that vanish without an error

### An `NSStatusItem` created before `setActivationPolicy` is discarded

And the object keeps answering `isVisible = true` and `frame.width = 30`. The
app's log said everything was fine while nothing was drawn on screen.

Create the item inside `applicationDidFinishLaunching`, after the policy.

### A non-template image is black on a black background

A *template* image is the one macOS repaints to match the bar's background.
Setting `isTemplate = false` to be able to tint it red made the symbol be drawn
in its natural color (black) and vanish against the dark bar.

And `contentTintColor` **only tints template images**, so the intended red did
not happen either. The icon was invisible exactly while recording.

### In full screen there is no menu bar

An app whose only feedback is the tray icon has no feedback at all in the mode
most applications are used in. The way out is an `NSPanel` with
`level = .screenSaver` and a `collectionBehavior` that includes
`.fullScreenAuxiliary`.

### `IsSecureEventInputEnabled()` is a session-wide flag

It is not "password field in focus", despite what the name suggests. Any process
can turn it on (including one with no interface, in the background), and some
apps turn it on and forget to turn it off. An app that depends on it to decide
whether to paste can stay mute indefinitely because of another program.

### `security find-identity -v -p codesigning` filters by trust

A self-signed certificate never appears in that list, **even while working
perfectly** for `codesign`. Using that command as an existence test makes the
script recreate the certificate on every run. On macOS that revokes the
Accessibility permission every time, because TCC anchors on the certificate.

Use `security find-identity <keychain>`, without the filters.

### Hardened runtime is incompatible with third-party dylibs

Turning on `--options runtime` enables library validation, which refuses to load
code signed by another team. With Homebrew dylibs the app dies in dyld:

```
code signature not valid for use in process:
mapping process and mapped file (non-platform) have different Team IDs
```

There is no middle ground: either static linking, or no protection. For a process
that holds Accessibility (able to read and inject keys across the whole system),
the protection is worth the work of compiling statically.

---

## User state

### A scheduled restoration needs guards

Inserting text through the clipboard requires saving and giving back what was
there. Giving it back after a fixed delay, unconditionally, destroys data in two
ways:

1. **Any write in the following N ms is reverted**: a ⌘C by the user, Universal
   Clipboard, a clipboard manager.
2. **Two insertions inside the window** leave the first one's text in place of
   the original contents, permanently: the second one snapshots the pasteboard
   already contaminated by the first.

Three guards solve it: a **generation** per operation (only the most recent
restoration counts), the **inherited snapshot** of a pending restoration (it
gives back the original contents, not the intermediate ones) and the
**`changeCount`** (it gives up if someone wrote in between).

And mark the item with `org.nspasteboard.ConcealedType`, or every insertion
enters the history of clipboard managers and survives the restoration.

### A privacy comment ages with nobody watching

`main.swift` opened with: *"A single file, overwritten… the app keeps no history
of anything you said."* It was true when it was written. On 2026-08-29 there were
three copies of what the person said on disk: `historico.json` (30
transcriptions), `nevertype.log` (the text of **every** transcription of the
session, which no document mentioned and "Clear History" did not delete) and
`last.wav` (the whole recording, which "Clear History" did not delete either).

None of them was a behavior defect. The history is deliberate and documented.
The defect was the sentence: a categorical negative inside the source, for
whoever asked "does it keep what I said?". Today the log keeps time and size,
never the text; "Clear History" deletes the JSON and the WAV; and the comment
lists the files.

**Rule:** a privacy claim is checked against the disk (`ls` in the app's folder
after dictating), not against the intention of whoever wrote it.

---

## Shell

### `set -e` plus `pipefail` make fallbacks unreachable

```bash
load_ms=$(grep -i 'load time' "$log" | sed ... )
[ -n "$load_ms" ] || load_ms=0     # never runs
```

If the `grep` does not match, the pipeline returns non-zero, `set -e` takes the
script down at the assignment, and the next line does not run. Wrap it in
`{ grep ... || true; }`.

### `trap ... RETURN` does not fire on `exit`

A function that creates a temporary directory and cleans up with
`trap ... RETURN` leaves the temporary behind when the script exits through an
error. In our case a passwordless RSA key was left in `$TMPDIR`. Add a
`trap ... EXIT`.

### `osascript` to control an app asks for Automation authorization

Sending an Apple event to a new app requires a TCC grant, and macOS opens a
modal dialog, hanging the script until someone answers, with no hint of why.
Use `pkill` and wait for the process to disappear.

### A fixed `sleep` waiting for a process is not waiting

If the process takes longer than the `sleep`, the script carries on under a
false premise. In the installer, that made the person keep running the old
binary thinking they had updated. Wait for the condition, with a limit and an
explicit failure.

---

## Measurement

### Wall-clock time measures the disk cache too

The bench measured `wall − load_time` to estimate the "hot" cost. With the page
cache cold, the same model scored **5087 ms of wall-clock against 976 ms of
actual processing**. The ~4 s were the fault-in of 547 MB coming from disk,
which the internal "load" counter does not cover.

The verdict against the latency ceiling depended on whether the model was
cached or not. The fix: warm the cache before measuring, and use the process's
internal stopwatch.

### One sample is not a measurement

Latency declared within target based on **one** dictation, of the cheapest
possible size, read from the log the app itself writes. The number turned out
right, and the method did not support the conclusion: it measured no variance,
exercised no worst case, and the instrument was the very object being measured.

---

## The pattern behind almost all of them

The worst defects in this list have the same shape: **the program reported
health while reality was something else.**

The log said the icon had been drawn. The object said it was visible. The `grep`
found "metal". The counter said how long it took. The `try?` said it had
protected. None of them was lying: each answered precisely a question that was
not the one that mattered.

The rule that remained: **verify the effect, not the intention.** Enumerate the
device instead of searching for its name. Compare the bytes instead of the text.
Measure from outside the process. And when a failure path has never been
exercised, treat it as not implemented, because in four audits, no unexercised
failure path was correct.
