# What opening at login costs

Measured on 2026-08-28, macOS 26.2, Apple Silicon, model
`ggml-large-v3-turbo-q5_0.bin` (547 MB).

The app changes nothing at launch because of this option: it loads the model and
warms up exactly as it always did. What changes is **when** that bill is paid —
before, you picked the moment by opening the app; now it lands together with the
login.

## The number

Stopwatch from outside the process: from `open` until the line appears in the
app's log. Not the log measuring itself.

| | icon in the bar | ready to dictate | model load |
|---|---|---|---|
| **cold page cache** | 784 ms | **8303 ms** | 6874 ms |
| warm page cache | 142 ms | 951 ms | 178 ms |
| warm page cache (2nd) | 162 ms | 965 ms | 172 ms |

The warm-up is constant — 614 to 622 ms across the three runs. **The whole
difference is in reading 547 MB from disk: 6874 ms against ~175 ms, almost 39×.**

## Why the cold row is the one that matters here

Right after login the page cache is empty by definition. So the real cost of
opening at login is the top row, not the bottom one — and the measurements you
would take by hand, with the model already read once, give the wrong number by
an order of magnitude.

And 8303 ms is a **floor**, not a ceiling: it was measured in a session already
at steady state. On a real login it competes for disk and CPU with Spotlight,
iCloud and everything else that comes up along with it. The honest boot number
only comes out by restarting the machine.

## What this means in practice

The icon appears in 784 ms. What lags is being **ready to dictate**: in the
first ~8 s after login, holding Right ⌘ records, but the transcription waits for
the model.

The spec decided not to load the model on demand, leaving it to be revisited
with the measured number in hand. The number is here, and it does not change the
decision: nobody dictates eight seconds after turning the computer on. Loading on
demand would only push the same wait to the first dictation of the day — which
is precisely when the person is waiting for the text to appear.

What would change the decision is the icon taking long, and it does not.

## How to redo the measurement

**At boot, with no tooling at all:** restart, open the menu bar menu and read the
`Model: Metal · load N ms · warm-up N ms` line. The app already measures itself,
and that is the real cold load. It is the right way to redo this number — the
others below are for measuring outside of boot.

To time any launch, from outside the process:

```bash
bash scripts/build-app.sh
pkill -x NeverType
rm -f ~/Library/Application\ Support/NeverType/nevertype.log
# time from here until the "model:" line appears in the log
open build/NeverType.app
```

Just do not confuse the two: without restarting, the page cache is already warm
from the previous run and you measure 951 ms thinking you measured boot.
