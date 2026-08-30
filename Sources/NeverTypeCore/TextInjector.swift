import AppKit
import Carbon.HIToolbox

/// Inserts text where the cursor is, via the clipboard.
///
/// Paste, not type character by character: one `CGEvent` per character takes
/// tens of ms per letter — a dictated paragraph would take seconds, throwing away
/// the latency gain — and breaks in fields with autocomplete, which react to
/// every key. Pasting is atomic and works the same in AppKit, Electron and the
/// terminal.
///
/// The price is touching the user's pasteboard. That is why saving and restoring
/// is not polish: it is an obligation, and it holds even when the insertion fails.
public enum TextInjector {

    public enum Outcome: Equatable {
        case inserted
        /// The session's secure input is on (`IsSecureEventInputEnabled()`). It is
        /// a global flag: some process turned it on — a password field in focus is
        /// the common case, but any app can turn it on, and some forget to turn
        /// it off. The ⌘V was not posted; the text was left on the clipboard for
        /// the user to paste. Warning is better than pretending it pasted.
        case blockedBySecureInput
        /// The Accessibility API named the focused element and it takes no text:
        /// a button, a menu item, an image. The ⌘V was not posted, because there
        /// it would be an arbitrary shortcut in the application in front. The
        /// text was left on the clipboard, and the payload is the role that
        /// produced the refusal, so the log can name it. Only a positive answer
        /// gets here: see `PasteTarget`.
        case noEditableField(String)
        case failed(String)
    }

    /// Full copy of the pasteboard: every item, every type.
    ///
    /// Keeping only the string would lose images, files, HTML — everything the
    /// user had copied before dictating.
    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        static func capture(from pasteboard: NSPasteboard) -> Snapshot {
            let items = (pasteboard.pasteboardItems ?? []).map { item in
                item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { acc, type in
                    if let data = item.data(forType: type) { acc[type] = data }
                }
            }
            return Snapshot(items: items)
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()
            guard !items.isEmpty else { return }
            pasteboard.writeObjects(items.map { stored in
                let item = NSPasteboardItem()
                for (type, data) in stored { item.setData(data, forType: type) }
                return item
            })
        }
    }

    /// The delay that has been in use since the first version, and the value
    /// that applies when the person set nothing.
    ///
    /// Several apps read the pasteboard asynchronously after the ⌘V. Restoring
    /// too fast pastes the old contents. Nobody measured 0.6 s, and the attempt
    /// to replace the timer with an observed signal is written up in
    /// `.vibeflow/specs/devolucao-observada-do-pasteboard.md`: promised data does
    /// report the exact instant of the read, and it broke pasting in Slack, which
    /// reads in several steps. So the restoration stays on a timer, and 0.6 s
    /// stays the default, because it is the behavior already in use.
    ///
    /// Every comparable tool times this too. espanso restores after 300 ms and
    /// QuiCopy after 100 ms (backlog D1 carries the URL), which puts this
    /// project's number at twice the largest of them.
    public static let defaultRestoreDelay: TimeInterval = 0.6

    /// `UserDefaults` key, domain `com.nevertype.app`, a number in seconds.
    ///
    /// A preference and not a menu item: see the README's Known limitations. The
    /// cost of a wrong number falls on the person in two ways, and neither is
    /// visible from here. A delay too short restores before the destination app
    /// has read, and the paste lands with what they had copied before, inside
    /// their document. A delay too long keeps the dictation sitting on their
    /// clipboard for that long.
    public static let restoreDelayKey = "clipboardRestoreDelay"

    /// The ends the stored value is held to.
    ///
    /// The floor is the smallest number any comparable tool uses (QuiCopy's
    /// 100 ms). Below it the restoration effectively races the ⌘V that was just
    /// posted, and there is no signal saying the paste was consumed: that is the
    /// finding of the 2026-08-28 autopsy. The ceiling is the one
    /// `devolucao-observada-do-pasteboard.md` argued for, marked there as chosen
    /// and not measured; past it the person's own clipboard is unreachable for
    /// long enough to be the thing they notice.
    public static let restoreDelayRange: ClosedRange<TimeInterval> = 0.1...5.0

    /// How long to wait before restoring the pasteboard, in seconds.
    ///
    /// Read from `UserDefaults` on every insertion, never held in a variable, so
    /// changing the key takes effect on the next dictation with no relaunch.
    public static var restoreDelay: TimeInterval {
        resolvedRestoreDelay(UserDefaults.standard.object(forKey: restoreDelayKey) as? Double)
    }

    /// The rule, separated from `UserDefaults` so it can be exercised without
    /// writing to the domain of whoever runs the suite.
    ///
    /// A missing key and a value that is not a finite number both give the
    /// default. `object(forKey:)` is what distinguishes "absent" from a stored
    /// zero, which `double(forKey:)` cannot do.
    public static func resolvedRestoreDelay(_ stored: Double?) -> TimeInterval {
        guard let stored, stored.isFinite else { return defaultRestoreDelay }
        return min(max(stored, restoreDelayRange.lowerBound), restoreDelayRange.upperBound)
    }

    /// Mark that well-behaved clipboard managers honor so as not to record the
    /// item in their history. Without it, every dictation would enter Raycast's
    /// or Maccy's history and survive the restoration.
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// Generation of the insertion in progress, and the snapshot still to be restored.
    ///
    /// Without this the restoration was unconditional and destroyed user data in
    /// two ways, both reproduced in audit:
    ///
    /// 1. **Any write to the pasteboard in the 600 ms after a dictation was
    ///    reverted** — a ⌘C of yours, Universal Clipboard, a clipboard manager.
    /// 2. **Two dictations less than 600 ms apart** left the first one's text in
    ///    place of the original contents, permanently: the second `insert`
    ///    snapshotted the pasteboard already contaminated by the first.
    ///
    /// The generation makes only the most recent restoration count; the inherited
    /// snapshot makes it restore the **original** contents, not the intermediate
    /// ones; and the `changeCount` makes it give up if someone wrote in between.
    /// Indexed by pasteboard: the pending snapshot belongs to a specific
    /// pasteboard, not to the process. In production only `.general` exists, but
    /// treating it as global state made two distinct pasteboards interfere with
    /// each other — which the parallel tests exposed right away.
    private struct Pending {
        var generation: Int
        var snapshot: Snapshot
    }
    @MainActor private static var pending: [NSPasteboard.Name: Pending] = [:]

    /// The default read back: asks the pasteboard for the text it now holds.
    ///
    /// A named function and not a closure literal, so it reads like the other
    /// system calls this file receives by parameter
    /// (`IsSecureEventInputEnabled`, `postCommandV`, `PasteTarget.current`).
    private static func stringOnPasteboard(_ pasteboard: NSPasteboard) -> String? {
        pasteboard.string(forType: .string)
    }

    /// Leaves the dictation on the pasteboard, with no restoration scheduled.
    ///
    /// Where the two paths that decline to paste end up. Without a ⌘V there is
    /// nothing to restore, so the text stays there for the person to paste
    /// whenever they want, carrying the `concealed` mark so a clipboard manager
    /// still keeps out of it.
    @MainActor
    private static func leave(_ text: String, on pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: concealed)
        _ = pasteboard.writeObjects([item])
    }

    @MainActor
    @discardableResult
    public static func insert(_ text: String,
                              pasteboard: NSPasteboard = .general,
                              paste: (() -> Bool)? = nil,
                              secureInput: (() -> Bool)? = nil,
                              focus: (() -> PasteTarget.Decision)? = nil,
                              readBack: ((NSPasteboard) -> String?)? = nil) -> Outcome {
        guard !text.isEmpty else { return .failed("empty text") }

        // Secure input on: the app does not post the ⌘V. The original premise —
        // that macOS would drop the synthetic event — was never measured here;
        // what the code knows is the flag's value (whether refusing is right is
        // in backlog D3). Here the spec says to leave the text on the pasteboard
        // — and the previous version returned **before** touching it, so it left
        // nothing. Without pasting there is nothing to restore, so the text stays
        // there for the user to paste whenever they want.
        //
        // Mind the name: `IsSecureEventInputEnabled` is a session-wide flag, not
        // "password field in focus". Any process can turn it on, including in the
        // background, and some apps turn it on and forget to turn it off.
        if (secureInput ?? IsSecureEventInputEnabled)() {
            leave(text, on: pasteboard)
            return .blockedBySecureInput
        }

        // Second, the focus, and only a positive "this takes no text" stops
        // here. Every other answer pastes, including an Accessibility error and
        // a role nobody recognizes, because an app that goes mute after a
        // dictation looks broken in a way the old blind ⌘V never did. The rule
        // and the query both live in `PasteTarget`; the check is switchable off
        // under `PasteTarget.checkKey`.
        //
        // Runs after the secure input flag on purpose: with secure input on,
        // asking who has the focus decides nothing, since the app is not going
        // to paste either way.
        if case .notEditable(let role) = (focus ?? PasteTarget.current)() {
            leave(text, on: pasteboard)
            return .noEditableField(role)
        }

        let key = pasteboard.name
        let myGeneration = (pending[key]?.generation ?? 0) + 1

        // Inherits the snapshot of a restoration still pending: snapshotting now
        // would capture the previous dictation's text, not the user's contents.
        let snapshot = pending[key]?.snapshot ?? Snapshot.capture(from: pasteboard)
        pending[key] = Pending(generation: myGeneration, snapshot: snapshot)

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: concealed)
        guard pasteboard.writeObjects([item]) else {
            pending[key] = nil
            return .failed("could not write to the clipboard")
        }

        let stamp = pasteboard.changeCount

        // The bytes come back before the ⌘V goes out.
        //
        // espanso waits 300 ms at this point (`pre_paste_delay`), on the grounds
        // that firing the paste before the content is on the clipboard makes the
        // operation fail. Here there is nothing to wait for: `writeObjects` is
        // synchronous and its result is checked above, and the item carries
        // concrete bytes, with no data provider in this file to defer anything to
        // a later callback. So this asks the pasteboard for the text and compares
        // it, which costs one round trip to the pasteboard server. A 300 ms wait
        // would be half the cost of the whole dictation (~600 ms, backlog L1) and
        // would still prove nothing.
        //
        // Failing here means the pasteboard was cleared and our text did not
        // land, so a ⌘V would paste whatever is sitting there, which is the very
        // damage D1 describes. The person's contents go back, under the same
        // `changeCount` guard the scheduled restoration uses.
        guard (readBack ?? stringOnPasteboard)(pasteboard) == text else {
            if pasteboard.changeCount == stamp { snapshot.restore(to: pasteboard) }
            pending[key] = nil
            return .failed("the text did not reach the clipboard")
        }

        // Read once: the timer and whoever asks `restoreDelay` afterwards have to
        // agree, and the key can change between two dictations.
        let delay = restoreDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                // A newer insertion took over: it restores the snapshot.
                guard pending[key]?.generation == myGeneration else { return }
                // Someone wrote to the pasteboard after us. Restoring now would
                // erase what that person just copied.
                guard pasteboard.changeCount == stamp else {
                    pending[key] = nil
                    return
                }
                snapshot.restore(to: pasteboard)
                pending[key] = nil
            }
        }

        return (paste ?? postCommandV)() ? .inserted : .failed("could not send ⌘V")
    }

    /// Synthetic ⌘V.
    ///
    /// Posted with explicit flags and after the trigger has already been
    /// released, so there is no pending modifier to contaminate the event.
    private static func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return false }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
