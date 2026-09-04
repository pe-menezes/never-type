import Testing
@testable import NeverTypeCore

// One file per unit. Until 2026-09-03 both suites here sat in
// `AudioRecorderTests.swift`, where nobody looking for a hotkey test by file
// name would find them (backlog H5).

@Suite("Hotkey trigger")
struct HotkeyTriggerTests {
    private typealias T = HotkeyMonitor.Trigger

    /// The keyCode and mask behind a modifier trigger; nil for a mouse button.
    private func modifier(_ t: T) -> (keyCode: UInt16, deviceMask: UInt)? {
        if case .modifier(let keyCode, let deviceMask) = t.source { return (keyCode, deviceMask) }
        return nil
    }

    /// The trigger needs to be a pure modifier identified by side: the `.command`
    /// mask is set with either of the two ⌘, so only the keyCode plus the device
    /// mask tells the right one from the left.
    @Test("right ⌘ has a distinct keyCode and device mask")
    func rightCommandIsIdentifiedByCodeAndMask() {
        let t = modifier(T.rightCommand)
        #expect(t?.keyCode == 54)
        #expect(t?.deviceMask == 0x0010)
        #expect(t?.deviceMask != modifier(T.rightOption)?.deviceMask)
        #expect(t?.keyCode != modifier(T.rightOption)?.keyCode)
    }

    /// The choice is saved by keyCode, not by label: a label is interface text
    /// and changes; the keyCode is stable across macOS versions.
    @Test("the chosen key survives a round trip through the identifier")
    func triggerRoundTripsThroughID() {
        for option in T.all {
            #expect(T.named(option.id) == option)
        }
    }

    @Test("unknown or missing identifier returns no trigger")
    func unknownTriggerIsNil() {
        #expect(T.named(nil) == nil)
        #expect(T.named("999") == nil, "keyCode we do not know")
        #expect(T.named("Right ⌘") == nil, "a label is not an identifier")
    }

    /// Pure modifiers only: anything else would require swallowing the event
    /// with a CGEventTap, which the project refused.
    @Test("all options are pure modifiers and distinct from each other")
    func optionsAreDistinctPureModifiers() {
        let parts = T.all.compactMap(modifier)
        #expect(parts.count == T.all.count, "a quick pick is always a modifier key")
        #expect(Set(parts.map { $0.keyCode }).count == parts.count,
                "a repeated keyCode would make two options become one")
        #expect(Set(parts.map { $0.deviceMask }).count == parts.count,
                "a repeated mask would not tell the side")
    }

    @Test("every known modifier round-trips through its identifier")
    func everyModifierRoundTrips() {
        #expect(T.modifiers.count == 9, "both sides of ⌘ ⌥ ⌃ ⇧, plus Fn")
        for key in T.modifiers {
            #expect(T.named(key.id) == key, "\(key.label) did not come back from \(key.id)")
        }
    }

    /// The bare keyCode is what has been in `UserDefaults` since the menu first
    /// offered a choice. A new format would need a migration for nothing.
    @Test("a bare keyCode still resolves to the same key")
    func bareKeyCodeStillResolves() {
        #expect(T.named("54") == T.rightCommand)
        #expect(T.named("61") == T.rightOption)
        #expect(T.named("62") == T.rightControl)
    }

    @Test("left and right of the same key differ in mask and in label")
    func sidesDiffer() {
        let pairs: [(left: T, right: T)] = [
            (.leftCommand, .rightCommand), (.leftOption, .rightOption),
            (.leftControl, .rightControl), (.leftShift, .rightShift),
        ]
        for pair in pairs {
            #expect(modifier(pair.left)?.deviceMask != modifier(pair.right)?.deviceMask,
                    "\(pair.left.label) and \(pair.right.label) share a mask, and the side would be lost")
            #expect(modifier(pair.left)?.keyCode != modifier(pair.right)?.keyCode)
            #expect(pair.left.label.hasPrefix("Left "), "\(pair.left.label)")
            #expect(pair.right.label.hasPrefix("Right "), "\(pair.right.label)")
        }
    }

    @Test("mouse identifiers round-trip and the two main buttons resolve to nothing")
    func mouseButtonsRoundTrip() throws {
        let middle = try #require(T.mouseButton(3))
        #expect(middle.id == "mouse:3")
        #expect(middle.label == "Mouse button 3")
        #expect(T.named("mouse:3") == middle)
        #expect(T.named("mouse:4")?.source == .mouseButton(4))
        #expect(T.mouseButton(1) == nil, "the primary click is never a trigger")
        #expect(T.mouseButton(2) == nil, "the secondary click is never a trigger")
        #expect(T.named("mouse:2") == nil)
        #expect(T.named("mouse:") == nil)
        #expect(T.named("mouse:three") == nil)
    }

    @Test("Caps Lock and a regular key resolve to nothing")
    func capsLockAndRegularKeysResolveToNothing() {
        #expect(T.named("57") == nil, "Caps Lock cannot be held")
        #expect(T.named("0") == nil, "the A key would reach the app in front")
        #expect(T.modifier(keyCode: 57) == nil)
    }

    @Test("menu choices are the three quick picks, plus the current trigger when it is off the list")
    func menuChoicesAddTheCurrentTriggerWhenOffTheList() throws {
        #expect(T.menuChoices(current: .rightOption) == T.all)
        #expect(T.menuChoices(current: .leftControl) == T.all + [T.leftControl])
        let middle = try #require(T.mouseButton(3))
        #expect(T.menuChoices(current: middle) == T.all + [middle])
    }

    /// One press cannot mean both. The capture panel refuses the trigger for
    /// the hands-free role, and the three quick picks never go through the
    /// panel, so the monitor itself has to keep the two apart.
    @Test("choosing the hands-free key as the trigger clears the hands-free key")
    @MainActor
    func choosingTheHandsFreeKeyAsTheTriggerClearsIt() {
        let monitor = HotkeyMonitor()
        monitor.handsFreeTrigger = .rightOption
        monitor.trigger = .rightOption
        #expect(monitor.handsFreeTrigger == nil)
        #expect(monitor.trigger == .rightOption, "the trigger wins; it is the key the person just picked")

        monitor.handsFreeTrigger = .rightControl
        monitor.trigger = .rightCommand
        #expect(monitor.handsFreeTrigger == .rightControl, "a different key is left alone")
    }
}


/// The hands-free latch. Every path here is one that, without the separate state
/// machine, could only be exercised by pressing keys at exact milliseconds.
@Suite("Hands-free latch")
struct LatchTests {
    private typealias L = HotkeyMonitor.Latch

    @Test("a normal hold is still press and release")
    func normalHold() {
        var latch = L()
        #expect(latch.handle(.down(0)) == [.start])
        #expect(latch.handle(.up(L.tapThreshold + 0.1)) == [.finish])
        #expect(!latch.isLatched)
    }

    /// A modal permission alert keeps pumping events. Unless a refused start
    /// resets the gesture first, its release arms the double-tap window and a
    /// second attempt becomes hands-free without ever starting a recording.
    @Test("a rejected start resets the gesture before its release arrives")
    func rejectedStartResetsGesture() {
        var latch = L()
        #expect(latch.handle(.down(0)) == [.start])

        _ = latch.resolveStart(accepted: false)

        #expect(latch.handle(.up(0.08)) == [])
        #expect(latch.handle(.down(0.12)) == [.start],
                "the next press is a fresh attempt, not a hands-free latch")
    }

    /// A short tap does not conclude right away: it waits to see whether the second one comes.
    @Test("a short tap delays the conclusion and concludes on timeout")
    func shortTapWaitsThenFinishes() {
        var latch = L()
        #expect(latch.handle(.down(0)) == [.start])
        #expect(latch.handle(.up(0.05)) == [.armTimeout(L.tapWindow)],
                "a short tap cannot conclude before the second-tap window")
        #expect(latch.handle(.timeout) == [.finish])
    }

    @Test("double tap locks, and the recording goes on without the key")
    func doubleTapLatches() {
        var latch = L()
        _ = latch.handle(.down(0))
        _ = latch.handle(.up(0.05))
        #expect(latch.handle(.down(0.15)) == [.disarmTimeout, .latch])
        #expect(latch.isLatched)
        // The second tap's `up` cannot finish anything.
        #expect(latch.handle(.up(0.2)) == [])
        #expect(latch.isLatched)
    }

    @Test("locked, one tap finishes and transcribes")
    func tapStopsLatched() {
        var latch = L()
        _ = latch.handle(.down(0)); _ = latch.handle(.up(0.05)); _ = latch.handle(.down(0.15))
        #expect(latch.handle(.down(5)) == [.finish])
        #expect(!latch.isLatched)
        #expect(latch.handle(.up(5.05)) == [], "the following up is ignored")
    }

    @Test("locked, Esc discards")
    func escapeCancelsLatched() {
        var latch = L()
        _ = latch.handle(.down(0)); _ = latch.handle(.up(0.05)); _ = latch.handle(.down(0.15))
        #expect(latch.handle(.escape) == [.cancel])
        #expect(!latch.isLatched)
    }

    /// The deliberate difference between the two modes: while holding, a regular
    /// key means "this was a shortcut"; in hands-free, typing is just typing.
    @Test("locked, a regular key does NOT cancel")
    func otherKeyDoesNotCancelLatched() {
        var latch = L()
        _ = latch.handle(.down(0)); _ = latch.handle(.up(0.05)); _ = latch.handle(.down(0.15))
        #expect(latch.handle(.otherKey) == [])
        #expect(latch.isLatched, "cancelling a long dictation because of a key kills the mode")
    }

    @Test("holding, a regular key cancels as before")
    func otherKeyCancelsHold() {
        var latch = L()
        _ = latch.handle(.down(0))
        #expect(latch.handle(.otherKey) == [.cancel])
    }

    @Test("a regular key in the second-tap window also cancels")
    func otherKeyCancelsWhileWaiting() {
        var latch = L()
        _ = latch.handle(.down(0)); _ = latch.handle(.up(0.05))
        #expect(latch.handle(.otherKey) == [.disarmTimeout, .cancel])
    }

    @Test("out-of-order event does nothing")
    func strayEventsAreIgnored() {
        var latch = L()
        #expect(latch.handle(.up(0)) == [], "release without having pressed")
        #expect(latch.handle(.timeout) == [], "timeout with no window armed")
        #expect(latch.handle(.otherKey) == [], "regular key with nothing in progress")
    }

    /// Off, the mode leaves the table. The release concludes on its own,
    /// nothing is armed, and the 300 ms a short tap used to spend waiting for a
    /// second one comes back.
    @Test("with hands-free off, a tap and a hold both end on the release")
    func handsFreeOffEndsOnTheRelease() {
        var latch = L(handsFree: false)
        #expect(latch.handle(.down(0)) == [.start])
        #expect(latch.handle(.up(0.05)) == [.finish],
                "a short tap has no second tap to wait for, so no window is armed")

        #expect(latch.handle(.down(1)) == [.start])
        #expect(latch.handle(.up(1 + L.tapThreshold + 0.1)) == [.finish],
                "the ordinary hold is untouched")
    }

    /// The state that locking goes through is never entered, so there is no
    /// state left for a second tap to lock from.
    @Test("with hands-free off, two taps do not lock")
    func handsFreeOffDoesNotLatch() {
        var latch = L(handsFree: false)
        _ = latch.handle(.down(0))
        _ = latch.handle(.up(0.05))

        #expect(latch.handle(.down(0.15)) == [.start],
                "the second tap opens a new dictation, and nothing locks")
        #expect(!latch.isLatched)
        #expect(latch.handle(.up(0.2)) == [.finish])
        #expect(!latch.isLatched)
        #expect(latch.handle(.timeout) == [], "no window was ever armed to expire")
    }

    // The hands-free key: press asks, release decides.

    /// The lock waits for the app to say the recording began. Without that
    /// order, a refused start (no Accessibility, no microphone, a recorder
    /// error) would play the lock tone and show the locked pill over nothing.
    @Test("a toggle from idle asks to start, and the release locks")
    func toggleFromIdleStartsThenLocks() {
        var latch = L()
        #expect(latch.handle(.toggleDown) == [.start])
        #expect(!latch.isLatched, "nothing is locked before the app answers")
        #expect(latch.resolveStart(accepted: true) == [], "the release is what locks")
        #expect(!latch.isLatched)
        #expect(latch.handle(.toggleUp) == [.latch])
        #expect(latch.isLatched)
        #expect(latch.handle(.up(0.4)) == [], "a release cannot finish a locked recording")
    }

    @Test("a refused start after a toggle leaves nothing armed")
    func refusedStartAfterToggleLeavesIdle() {
        var latch = L()
        _ = latch.handle(.toggleDown)
        #expect(latch.resolveStart(accepted: false) == [])
        #expect(!latch.isLatched)
        #expect(latch.handle(.toggleUp) == [], "the release of a refused start does nothing")
        #expect(latch.handle(.down(1)) == [.start], "the next press is a fresh attempt")
        #expect(latch.handle(.up(1 + L.tapThreshold + 0.1)) == [.finish], "and it ends as an ordinary hold")
    }

    /// The defect this rule exists for. With a modifier as the hands-free key,
    /// every shortcut that starts with it reaches the monitor alone first. On
    /// the press-locks rule the recording started, locked, and then ignored the
    /// letter, because a locked recording is not cancelled by typing: the
    /// microphone stayed open with no cap.
    @Test("a regular key while the hands-free key is held cancels, as in a shortcut")
    func regularKeyDuringTheHandsFreeKeyCancels() {
        var latch = L()
        #expect(latch.handle(.toggleDown) == [.start])
        _ = latch.resolveStart(accepted: true)
        #expect(latch.handle(.otherKey) == [.cancel], "⌃C, with Left ⌃ as the hands-free key")
        #expect(!latch.isLatched)
        #expect(latch.handle(.toggleUp) == [], "the release lands in idle and locks nothing")
    }

    @Test("Esc while the hands-free key is held cancels too")
    func escapeDuringTheHandsFreeKeyCancels() {
        var latch = L()
        _ = latch.handle(.toggleDown)
        _ = latch.resolveStart(accepted: true)
        #expect(latch.handle(.escape) == [.cancel])
        #expect(!latch.isLatched)
    }

    @Test("a toggle while holding locks on the release, without the second tap")
    func toggleWhileHoldingLocks() {
        var latch = L()
        _ = latch.handle(.down(0))
        #expect(latch.handle(.toggleDown) == [], "the recording is already running")
        #expect(latch.handle(.toggleUp) == [.latch])
        #expect(latch.isLatched)
        #expect(latch.handle(.up(0.5)) == [], "the trigger's release cannot finish a locked recording")
    }

    @Test("a regular key cancels the chord too, the same as a plain hold")
    func regularKeyDuringTheChordCancels() {
        var latch = L()
        _ = latch.handle(.down(0))
        _ = latch.handle(.toggleDown)
        #expect(latch.handle(.otherKey) == [.cancel])
        #expect(!latch.isLatched)
    }

    @Test("a toggle while waiting for the second tap disarms the timer and locks on the release")
    func toggleWhileWaitingLocksAndDisarms() {
        var latch = L()
        _ = latch.handle(.down(0))
        _ = latch.handle(.up(0.05))
        #expect(latch.handle(.toggleDown) == [.disarmTimeout])
        #expect(latch.handle(.toggleUp) == [.latch])
        #expect(latch.isLatched)
        #expect(latch.handle(.timeout) == [], "the disarmed window cannot expire")
    }

    @Test("a toggle while locked finishes on the release")
    func toggleWhileLockedFinishes() {
        var latch = L()
        _ = latch.handle(.toggleDown)
        _ = latch.resolveStart(accepted: true)
        _ = latch.handle(.toggleUp)
        #expect(latch.handle(.toggleDown) == [], "the press asks")
        #expect(latch.isLatched, "still locked while the key is down")
        #expect(latch.handle(.toggleUp) == [.finish])
        #expect(!latch.isLatched)
    }

    /// Locked, a regular key does not cancel, and a shortcut that uses the
    /// hands-free key must not end the dictation either: it only takes the
    /// finish back.
    @Test("a shortcut with the hands-free key while locked keeps the lock")
    func shortcutWhileLockedKeepsTheLock() {
        var latch = L()
        _ = latch.handle(.toggleDown)
        _ = latch.resolveStart(accepted: true)
        _ = latch.handle(.toggleUp)

        _ = latch.handle(.toggleDown)
        #expect(latch.handle(.otherKey) == [], "⌃C while locked")
        #expect(latch.isLatched)
        #expect(latch.handle(.toggleUp) == [], "the release no longer finishes")
        #expect(latch.isLatched, "the dictation the mode exists to allow is still running")
    }

    @Test("Esc while the hands-free key is held for the finish discards")
    func escapeWhileFinishPendingDiscards() {
        var latch = L()
        _ = latch.handle(.toggleDown)
        _ = latch.resolveStart(accepted: true)
        _ = latch.handle(.toggleUp)
        _ = latch.handle(.toggleDown)
        #expect(latch.handle(.escape) == [.cancel])
        #expect(!latch.isLatched)
    }

    /// What a change of the hands-free key abandons, and what it does not.
    @Test("only a gesture holding the hands-free key counts as holding it")
    func holdingTheHandsFreeKeyIsOnlyItsOwnGesture() {
        var latch = L()
        #expect(!latch.isHoldingHandsFreeKey, "idle")

        _ = latch.handle(.down(0))
        #expect(!latch.isHoldingHandsFreeKey, "the trigger's hold is not this key")

        _ = latch.handle(.toggleDown)
        #expect(latch.isHoldingHandsFreeKey, "arming the lock")

        _ = latch.handle(.toggleUp)
        #expect(!latch.isHoldingHandsFreeKey, "locked, and every way out is key-agnostic")
    }

    /// Off, the mode leaves the table for the second key as well: a key that
    /// locks with the mode off would contradict "only records while held".
    @Test("with hands-free off the toggle does nothing")
    func handsFreeOffIgnoresTheToggle() {
        var latch = L(handsFree: false)
        #expect(latch.handle(.toggleDown) == [], "idle")
        #expect(latch.handle(.toggleUp) == [])
        #expect(latch.resolveStart(accepted: true) == [], "nothing was starting")
        #expect(!latch.isLatched)
        _ = latch.handle(.down(0))
        #expect(latch.handle(.toggleDown) == [], "holding")
        #expect(latch.handle(.up(0.5)) == [.finish], "the hold ends as before")
    }
}
