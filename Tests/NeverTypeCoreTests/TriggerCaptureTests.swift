import Testing
@testable import NeverTypeCore

/// The capture rule. Every branch here is one the panel would need a keyboard,
/// a mouse and a window to reach; the rule reaches them with a list of inputs.
@Suite("Trigger capture")
struct TriggerCaptureTests {
    private typealias T = HotkeyMonitor.Trigger
    private typealias C = TriggerCapture

    private func code(of key: T) -> UInt16 {
        if case .modifier(let code, _) = key.source { return code }
        return 0
    }

    private func mask(of key: T) -> UInt {
        if case .modifier(_, let mask) = key.source { return mask }
        return 0
    }

    /// `.flagsChanged` with the key's own bit set: the press.
    private func press(_ key: T) -> C.Input {
        .flagsChanged(keyCode: code(of: key), rawFlags: mask(of: key))
    }

    /// `.flagsChanged` with the bit cleared: the release.
    private func release(_ key: T) -> C.Input {
        .flagsChanged(keyCode: code(of: key), rawFlags: 0)
    }

    @Test("a right-side modifier is accepted on its release")
    func rightSideAcceptedOnRelease() {
        for key in [T.rightCommand, .rightOption, .rightControl, .leftControl] {
            var capture = C(purpose: .pushToTalk)
            #expect(capture.handle(press(key)) == .waiting, "\(key.label): the press decides nothing yet")
            #expect(capture.handle(release(key)) == .accepted(key), "\(key.label)")
        }
    }

    @Test("Fn, Left ⌥ and a mouse button are accepted with their caveat")
    func acceptedWithCaveat() throws {
        var capture = C(purpose: .pushToTalk)
        _ = capture.handle(press(.fn))
        #expect(capture.handle(release(.fn)) == .acceptedWithCaveat(.fn, .fnSystemAction))

        capture = C(purpose: .pushToTalk)
        _ = capture.handle(press(.leftOption))
        #expect(capture.handle(release(.leftOption)) == .acceptedWithCaveat(.leftOption, .leftOptionAccents))

        capture = C(purpose: .pushToTalk)
        let button4 = try #require(T.mouseButton(4))
        #expect(capture.handle(.mouseDown(button: 4)) == .waiting)
        #expect(capture.handle(.mouseUp(button: 4)) == .acceptedWithCaveat(button4, .clickReachesFrontApp))
    }

    @Test("Shift, Left ⌘ and Caps Lock are refused on the press, each with its reason")
    func refusedOnThePress() {
        var capture = C(purpose: .pushToTalk)
        #expect(capture.handle(press(.leftShift)) == .refused(.everyCapitalLetter))
        #expect(capture.handle(release(.leftShift)) == .waiting, "the release of a refused key says nothing")
        #expect(capture.handle(press(.rightShift)) == .refused(.everyCapitalLetter))
        #expect(capture.handle(press(.leftCommand)) == .refused(.everyShortcut))
        #expect(capture.handle(.flagsChanged(keyCode: 57, rawFlags: 0x10000)) == .refused(.togglesKeyboardState),
                "Caps Lock")
    }

    @Test("a regular key is refused, alone or on top of a held modifier, and the release that follows accepts nothing")
    func regularKeyRefused() {
        var capture = C(purpose: .pushToTalk)
        #expect(capture.handle(.keyDown(keyCode: 0)) == .refused(.reachesFrontApp), "the A key, alone")
        #expect(capture.handle(press(.rightCommand)) == .waiting)
        #expect(capture.handle(.keyDown(keyCode: 9)) == .refused(.reachesFrontApp), "⌘V")
        #expect(capture.handle(release(.rightCommand)) == .waiting,
                "the hold was spoiled, so its release accepts nothing")
    }

    @Test("a second modifier on top of a held one is refused as a combination")
    func combinationRefused() {
        var capture = C(purpose: .pushToTalk)
        #expect(capture.handle(press(.rightCommand)) == .waiting)
        // ⌥ goes down with ⌘ still held: both bits set, as macOS reports it.
        #expect(capture.handle(.flagsChanged(keyCode: code(of: .rightOption),
                                             rawFlags: mask(of: .rightCommand) | mask(of: .rightOption)))
                == .refused(.reachesFrontApp))
        #expect(capture.handle(.flagsChanged(keyCode: code(of: .rightOption), rawFlags: mask(of: .rightCommand)))
                == .waiting, "⌥ released with ⌘ still down: the rule holds nothing any more")
        #expect(capture.handle(release(.rightCommand)) == .waiting)
    }

    @Test("Escape cancels, from idle and from a hold")
    func escapeCancels() {
        var capture = C(purpose: .pushToTalk)
        #expect(capture.handle(.keyDown(keyCode: 53)) == .cancelled)

        capture = C(purpose: .pushToTalk)
        _ = capture.handle(press(.rightCommand))
        #expect(capture.handle(.keyDown(keyCode: 53)) == .cancelled)
    }

    @Test("the secondary click is refused")
    func secondaryClickRefused() {
        var capture = C(purpose: .pushToTalk)
        #expect(capture.handle(.rightMouseDown) == .refused(.secondaryClick))
        #expect(capture.handle(.mouseDown(button: 2)) == .refused(.secondaryClick),
                "if a main button ever arrived as a mouse input")
        #expect(capture.handle(.mouseDown(button: 1)) == .refused(.secondaryClick))
    }

    @Test("for hands-free, the push-to-talk key is refused")
    func handsFreeRefusesThePushToTalkKey() {
        var capture = C(purpose: .handsFree(pushToTalk: .rightCommand))
        _ = capture.handle(press(.rightCommand))
        #expect(capture.handle(release(.rightCommand)) == .refused(.alreadyThePushToTalkKey))
        _ = capture.handle(press(.rightOption))
        #expect(capture.handle(release(.rightOption)) == .accepted(.rightOption))
    }

    @Test("a release with nothing held is ignored")
    func strayReleaseIgnored() {
        var capture = C(purpose: .pushToTalk)
        #expect(capture.handle(release(.rightOption)) == .waiting,
                "the ⌥ that opened the diagnostics menu, released over the panel")
        #expect(capture.handle(.mouseUp(button: 4)) == .waiting)
        #expect(capture.handle(.flagsChanged(keyCode: 999, rawFlags: 0)) == .waiting,
                "a modifier the app does not know")
    }
}
