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

    /// How long to wait before restoring the pasteboard.
    ///
    /// Several apps read the pasteboard asynchronously after the ⌘V. Restoring
    /// too fast pastes the old contents. Generous on purpose: the cost of waiting
    /// is invisible, the cost of getting it wrong is pasting the wrong thing.
    public static let restoreDelay: TimeInterval = 0.6

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

    @MainActor
    @discardableResult
    public static func insert(_ text: String,
                              pasteboard: NSPasteboard = .general,
                              paste: (() -> Bool)? = nil,
                              secureInput: (() -> Bool)? = nil) -> Outcome {
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
            pasteboard.clearContents()
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            item.setData(Data(), forType: concealed)
            _ = pasteboard.writeObjects([item])
            return .blockedBySecureInput
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
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
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
