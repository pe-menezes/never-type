# Hotfix: vocabulary-window-hides-the-orb

origin: session
status: verified

## Symptom
Closing the vocabulary window makes the floating orb disappear. It comes back
only when the next recording starts. Seen on 2026-09-03 through the capture
panel, which had copied the vocabulary window's closing line: the author chose
a key, the panel closed, and the orb was gone until the next dictation. The
panel was changed the same day (`TriggerCapturePanel.swift`, `windowWillClose`,
`previous.activate(from: .current, options: [])`) and the orb stayed; the
vocabulary window still has the original line.

## Checkpoint
hypothesis: `NSApp.hide(nil)` in `VocabularyWindow.windowWillClose`
(`Sources/NeverType/VocabularyWindow.swift`) hides every window of the app,
the orb included. It was put there to give the focus back to the app the
person was in, and it does that too.
falsification_test: closing the vocabulary window with the line replaced by
handing the activation to the app that was in front, and the orb still
vanishing.
blind_spots: whether the orb comes back on its own on any event other than a
recording; not checked, and not needed for the fix.

## Preservation
- Closing the vocabulary window still gives the focus back to the app the
  person was in: the keyboard goes somewhere visible.
- The vocabulary window still saves on close.
- The capture panel keeps behaving as it does since 2026-09-03.

## Eliminated / Evidence

## Root cause
`NSApp.hide(nil)` in `VocabularyWindow.windowWillClose`. `hide` deactivates
the app and hides all of its windows that can hide; the orb panel can, so it
went with the vocabulary window. The line was the only way the window knew to
return the focus.

## Fix
files_changed: Sources/NeverTypeCore/FocusHandback.swift (new), Sources/NeverType/VocabularyWindow.swift

`FocusHandback` (NeverTypeCore) remembers the app in front before this app
activates, and on close hands the activation to it, macOS 14's cooperative
activation; it hides the app only as the fallback, with nothing remembered,
with this app itself remembered, or with an activation the system refused.
The system calls (frontmost app, activate, hide) enter as parameters with
defaults, the same shape as `TextInjector.insert(secureInput:)`, so every
branch has a test. `VocabularyWindow` calls `remember()` in `show()` before
`NSApp.activate`, only when the window is not already open, and `giveBack()`
in `windowWillClose` where `NSApp.hide(nil)` was.

## DoD
- [x] `FocusHandbackTests.swift` red before the fix, for the two reasons named
  (`NSApp.hide(` present, `FocusHandback` absent), green after.
- [x] `swift test` green: 160 tests in 18 suites.
- [x] `Sources/NeverType/VocabularyWindow.swift` no longer contains
  `NSApp.hide(`.
- [ ] By hand: open the vocabulary window from the menu, close it, and the orb
  stays; the keyboard goes back to the app that was in front. Pending the
  author's next install.

## Regression
WHEN the vocabulary window closes, having been opened from another app in
front THEN this app is not hidden, so the orb stays on screen, and the app
that was in front is active again
test: Tests/NeverTypeCoreTests/FocusHandbackTests.swift
oracle_type: derived
reproduction: real
verification: red-green

The window lives in the executable target, which the test target cannot
import, so the oracle reads the window's source: no `NSApp.hide(` in
`VocabularyWindow.swift`, and `FocusHandback` in it. The rule itself has four
tests with the system calls replaced: gives the focus back and hides nothing;
hides only with nothing in front or a refused activation; never activates
itself; forgets the app after giving the focus back.

## Deviations
- `TriggerCapturePanel.swift` keeps its own inline copy of the same hand-back
  (2026-09-03), and its comment still says the vocabulary window hides the
  app. Deferred, one call one bug: consolidating the panel onto
  `FocusHandback` and fixing that comment is a follow-up, a third code file
  beyond this hotfix's budget.
- The by-hand check of the orb staying after closing the vocabulary window
  waits for the author's next install; the mechanism is the one the author
  confirmed on the capture panel on 2026-09-03.
