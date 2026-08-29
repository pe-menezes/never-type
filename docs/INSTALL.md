Português: [INSTALL.pt-BR.md](INSTALL.pt-BR.md)

# Installing NeverType

> **This document is for a coding agent to execute**, and it is not meant for a
> human to read end to end. If you are human and just want to use the app: ask
> your agent to follow this file, or go to the `README.md`.

NeverType is local voice dictation for macOS. It is **compiled on the machine of
whoever installs it**: there is no prebuilt binary, and that is on purpose. Each
installation generates its own local certificate, and a locally compiled app
does not go into quarantine, so Gatekeeper never shows up.

## Before you start

**Read `docs/pitfalls.md`.** Those are the mistakes already made in this project,
with the measured cost of each. Several of them would pass code review and only
showed up when running.

**Four things in this walkthrough need the person, and no agent solves them:**
installing the Command Line Tools, granting Microphone, granting Accessibility,
and dictating the sentence that proves the installation. They are marked
**STOP AND ASK** below, with the text to say.

## What you can fix on your own, and what you cannot

| You can | Stop and ask |
|---|---|
| `brew install cmake` | Anything involving `security list-keychains` |
| Run `xcode-select --install` and wait | Deleting `~/Library/Keychains/nevertype-signing.keychain-db` |
| Rebuild after a build failure | Writing outside the repository and `~/Library/Application Support/NeverType/` |
| Retry an interrupted download | Installing into `/Applications` without write permission |
| Delete an invalid model and download again | Disabling a check to make a step pass |

The keychain line is not excess caution. `security list-keychains -s`
**replaces the whole list**: getting it wrong there removes the person's login
keychain, and they lose their Wi-Fi, Safari and app passwords. `build-app.sh`
has a guard rail for exactly that reason. Do not improvise on that command.

And deleting the signing keychain **revokes the Accessibility permission**: the
person will have to grant everything again.

## 1. Prerequisites

```bash
uname -s   # must be Darwin
uname -m   # must be arm64
sw_vers -productVersion   # must be 14 or higher
```

Intel or an old macOS: **stop**. Without Metal, transcription is ~11× slower, and
the project refuses on purpose.

### Command Line Tools: STOP AND ASK

```bash
xcode-select -p   # if it fails, they are not installed
```

If missing, run `xcode-select --install` and tell the person:

> A macOS window opened asking to install the Command Line Tools. Click
> **Install** and accept the terms. It takes a few minutes. Let me know when it
> finishes.

Full Xcode is **not** required. Confirm with `xcode-select -p` before moving on;
do not accept "I already installed it" without checking.

### cmake

```bash
command -v cmake || brew install cmake
```

Only to build. It is not a runtime dependency.

## 2. Build and install

```bash
git clone <repository-url> nevertype && cd nevertype
bash scripts/build-app.sh
bash scripts/install.sh
```

`build-app.sh` clones whisper.cpp at a pinned commit, checks it, compiles it
statically and signs. **It takes a few minutes the first time.** That is normal;
do not interrupt it.

`install.sh` refuses early what cannot be fixed later (non-Darwin, non-arm64,
`/Applications` not writable), installs, verifies the signature and checks the
model. It only builds if `build/NeverType.app` does not exist yet: after changing
code, or after a `git pull` done by hand, run `build-app.sh` first, otherwise it
installs the old `build/` without a word. `update.sh` already does this in the
right order.

If it complains about `/Applications` without write permission: **stop and
ask**. There is an alternative path (`~/Applications/`), but that is the person's
decision to make. And if they choose that path, be aware that
`verify-install.sh` and `update.sh` only know `/Applications`: they will say the
app is not installed. Verification then comes down to dictating.

## 3. The model

It is 547 MB and it **does not ship in the app**. `install.sh` warns if it is
missing.

```bash
bash scripts/setup-bench.sh   # downloads and converts three models; requires Homebrew and python3
bash scripts/fetch-model.sh   # validates and installs it in the right place
```

`setup-bench.sh` is the model bench, and it does more than install: it requires
**Homebrew** (it installs `whisper-cpp` through it) and **python3** (it creates a
venv with torch in `.cache/`), and it downloads, converts and quantizes
**three** models (turbo, medium and small). It takes a while; the time was not
measured. If `brew` does not exist, the script stops: installing Homebrew is the
person's decision. **Ask.**

### If the network blocks the download

It happens on corporate networks. The classic symptom is a file of the wrong
size, or an **HTML error page saved under the model's name**, and no connection
error to go with it. That is why the validation checks the magic, in
hexadecimal, and ignores the extension.

Copying from another machine that already has it is a valid path, **but the file
has to come in through the repository**, never straight into the destination:

```bash
cp /wherever/it/came/from/ggml-large-v3-turbo-q5_0.bin models/
bash scripts/fetch-model.sh
```

`fetch-model.sh` validates magic and size (at least 400 MB, for a 547 MB model)
before promoting, and deletes the copy if it does not come out valid. Copying
straight into `~/Library/Application Support/` skips that validation: the app
checks again when it opens, refuses the file, opens with the slashed icon, and the
"Model:" line in the menu carries the message with the script to run. The person
discovers the problem in the menu, before the first dictation.

## 4. Permissions

Two, and the app asks for both when it opens. **Both need the person.**

### Microphone: STOP AND ASK

> macOS is going to ask whether NeverType may use the microphone. Click
> **Allow**. Without it there is no audio.

### Accessibility: STOP AND ASK

This is the easiest one to miss, and the most likely failure mode of a fresh
installation. Without it the app opens and **does not react to the key**. It
warns (the slashed icon, `mic.slash`, "Accessibility: missing" and "Open
Accessibility Settings…" in the menu, a line in `nevertype.log`, and macOS's own
prompt), but none of that reaches someone who opens neither the menu nor the
log.

> Open **System Settings › Privacy & Security › Accessibility** and **turn on
> NeverType** in the list. If it is not there, click the **+** and choose
> `/Applications/NeverType.app`.
>
> That is what lets the app receive the global key. Without it, the app opens
> and looks like it works, but holding the key does nothing.
>
> After turning it on, **quit NeverType from the menu bar menu and open it
> again**.

Do not continue until the person confirms they did it.

## 5. Verify

```bash
bash scripts/verify-install.sh
```

It checks the installed app, the signature, a live process and a model valid by
bytes. It exits with a non-zero code and lists everything that is wrong at once.

**It does not verify permissions, and they cannot be verified from the outside.**
The only proof is the dictation inserting text.

### The test that closes the installation: STOP AND ASK

> Open any text field, like a message or a document. Spotlight's search does not
> count.
>
> Hold the **Right ⌘**, say a sentence, and release.
>
> The text has to appear where the cursor is.

It appeared: done. It did not: go back to Accessibility. It is the cause in
almost every case.

## 6. Update

When the person says *"update it for me"*, it is a single command:

```bash
cd nevertype && bash scripts/update.sh
```

It checks whether there is a new version by comparing three things: the
**installed** commit (stamped in the bundle), the **local** commit and the
**remote** one. If they are all the same, it does nothing. If they differ, it
pulls, builds, installs and runs the verification.

**It stops in six cases. In two of them you stop as well:**

- **Uncommitted local changes.** It lists them and refuses. **Do not run
  `git reset --hard` or `git stash` on your own.** Committing, stashing or
  discarding is the person's decision, and discarding deletes their work.
- **A pull that is not a fast-forward.** The local branch diverged from the
  remote. Resolving that on your own can lose their commits. Ask.

In the other four, the message says what to do: the directory is not a git clone
(clone it and run `build-app.sh` and `install.sh`); the clone has no remote; the
`fetch` failed (network); the branch does not track any remote branch (it gives
you the command).

The permissions survive the update, because the signing certificate is stable
across builds on the same machine. That is why
`~/Library/Keychains/nevertype-signing.keychain-db` **must never be deleted**:
deleting it revokes Accessibility and the person has to grant everything again.

After updating, the test is still the same: **dictate a sentence.**

The installed version also shows in the menu bar menu, under "Version:".

## How to use

- Hold **Right ⌘**, speak, release. The text appears where the cursor is.
- **Two quick taps** lock into hands-free; one tap finishes; **Esc** discards.
- Any regular key, or Esc, during the hold cancels and discards the audio.
- The floating pill shows the microphone level while recording; if the bars do
  not move, no sound is coming in.
- The menu bar menu has the history, the key choice and the vocabulary. "Clear
  History" deletes the stored text and the audio of the last dictation.
