# NeverType

Voice dictation with local transcription on macOS, Portuguese only. Holding the
key (Right ⌘ by default; Right ⌥ or ⌃ from the menu) records, releasing
transcribes, two taps lock into hands-free, and the text is inserted wherever
the cursor is. **No network calls at run time**: it is the constraint that
justifies the project's existence, and there is a DoD check verifying it in the
code and in the binary.

Accessory menu bar app (no Dock; the only windows are the floating pill and the
vocabulary one). macOS 14+, Apple Silicon.
Swift 6 with strict concurrency, SwiftPM, **no Xcode**: Command Line Tools only.

## Before writing code, read

1. `.vibeflow/index.md`: structure, budget per task, known debts (`.vibeflow/`
   is in Portuguese; see Language below)
2. `.vibeflow/conventions.md`: conventions and the **Don'ts** section
3. The relevant pattern docs in `.vibeflow/patterns/` (there are eight)
4. `docs/pitfalls.md`: the mistakes already made, with the measured cost

The fourth is not optional. Several defects in this project **would pass code
review** and only showed up when running. Most of them had the program
reporting that everything was fine while it was not.

## The rules that most often catch newcomers

- **Verify the effect, not the intention.** Searching a log for a word does not
  prove something happened: a CPU run's log contains 37 lines with "metal".
  Enumerate the device, compare the bytes, measure from outside the process.
- **A magic number is compared in hex**, and never alone. `head -c 4` of a ggml
  model is `lmgg`, not `ggml`. A truncated file has the right bytes.
- **Concurrency isolation goes in the type.** `MainActor.assumeIsolated` only
  where the API documents the main thread **and** the order of events matters. A
  closure written inside a `@MainActor` method **inherits** the isolation by
  inference. That took the app down twice.
- **System state is queried, never stored.** Permissions change from outside.
- **swift-testing, never XCTest.** XCTest requires full Xcode.
- **Every failure path has to be exercisable.** If it cannot be exercised, it
  does not count as implemented: in four audits, no unexercised failure path
  was correct.
- **A comment explains why, and what broke before**, with the measured number.
  It does not explain what the code does.

## Commands

**First thing, on a fresh clone:**

```bash
bash scripts/build-app.sh     # compiles the static whisper.cpp into vendor/
```

`vendor/` is not versioned (they are binaries), and without it `swift build`
fails with `could not build Objective-C module 'CWhisper'`, a message that does
not say the cause. The script clones whisper.cpp at a pinned commit, checks it,
compiles it and stores the result. It takes a few minutes the first time, ~1 s
afterwards.

After that:

```bash
swift build && swift test     # 106 tests
bash scripts/install.sh       # installs into /Applications
bash scripts/bench.sh         # measures latency and quality per model
```

Outside version control and rebuildable: `models/` (1.2 GB on disk: the three
bench models; the app loads one, 547 MB), `vendor/` (static whisper.cpp),
`fixtures/` (recordings), `bench-out/`, `.cache/`, `build/`.

**Never delete** `~/Library/Keychains/nevertype-signing.keychain-db`: deleting
it revokes the Accessibility permission and the user has to grant it again.

## Language

English everywhere: code, APIs, comments, error messages, interface text, log
lines, test names, scripts, docs, and commit messages from here on (the commits
already in the log stay as they are). Two exceptions:

- `.vibeflow/` stays in Portuguese. It is the working notes of whoever drives
  the repo; it is read next to the code, not published with it.
- `README.md` and `docs/INSTALL.md` have Portuguese mirrors, `README.pt-BR.md`
  and `docs/INSTALL.pt-BR.md`, and a change to one side is a change to both.
  `INSTALL.pt-BR.md` exists because the four literal speech blocks in it are
  read aloud to the person installing, so their language is the installer's,
  not the repository's.

Names on disk keep what they were (`historico.json`, `vocabulario.json`,
`ultima-transcricao.txt`, the `somDasAcoes` key): renaming them would need a
migration for a gain no user sees. And the app transcribes Portuguese only
(`"pt"` in `Transcriber.swift`); that is product behavior, not a language rule.

## State

Works end to end: ~600 ms per dictation with the model warm, 106 tests. Nobody
besides the author has ever installed it.

One thing is missing: **a distributable package that does not require
compiling**. Every installation still compiles on its own machine. Open at
login, transcription history and custom vocabulary are off the list: they are
implemented (`LoginItem.swift`, `TranscriptHistory.swift`, `Vocabulary.swift`),
with tests, and what they still lack is checking in real use, noted item by
item in `.vibeflow/backlog.md`.

## Known and accepted risk

The app is signed with a local certificate, and macOS ties Microphone and
Accessibility to that certificate. Whoever already runs code on the machine can
use it. It is inherent to a local certificate; the alternative makes macOS
revoke the permission on every build. See the README's Security section before
touching `scripts/build-app.sh`.
