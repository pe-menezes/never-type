import Testing
@testable import NeverTypeCore

/// The decision rule alone, with no focused application anywhere near it.
///
/// What is tested here is what the code decides given an element with such and
/// such attributes. The query that produces the element talks to whatever has
/// the focus on the machine running the suite, which is neither reproducible nor
/// something a test may depend on.
///
/// The asymmetry the whole suite turns on: refusing to paste where pasting would
/// have worked leaves the person with a dictation they spoke and an app that did
/// nothing, so every uncertainty has to come back as "paste".
@Suite("Focus check before pasting")
struct PasteTargetTests {

    @Test("a text field takes the dictation")
    func textFieldIsEditable() {
        let decision = PasteTarget.decide(PasteTarget.Focus(role: "AXTextField", valueIsSettable: false))
        #expect(decision == .editable("AXTextField"))
        #expect(decision.allowsPaste)
    }

    @Test("a text area and a combo box take it too")
    func otherEditableRoles() {
        for role in ["AXTextArea", "AXComboBox"] {
            let decision = PasteTarget.decide(PasteTarget.Focus(role: role, valueIsSettable: false))
            #expect(decision == .editable(role), "\(role) had to be accepted, got \(decision)")
        }
    }

    /// The role list is three names long, and the world is not. An element that
    /// answers "you can set my value" takes text whatever it calls itself.
    @Test("a settable AXValue takes the dictation whatever the role is")
    func settableValueWins() {
        let decision = PasteTarget.decide(PasteTarget.Focus(role: "AXSomethingNobodyHasSeen",
                                                           valueIsSettable: true))
        #expect(decision == .editable("settable AXValue"))
    }

    /// The order of the rule, and the reason it is that order: the settable
    /// check runs before the refusal list, so a role that usually means "no
    /// text" never vetoes an element that just said it takes text.
    @Test("a settable value overrules a role from the refusal list")
    func settableValueBeatsTheRefusalList() {
        #expect(PasteTarget.rolesWithoutText.contains("AXStaticText"))
        let decision = PasteTarget.decide(PasteTarget.Focus(role: "AXStaticText", valueIsSettable: true))
        #expect(decision.allowsPaste, "a settable AXStaticText takes text, and got \(decision)")
    }

    @Test("a focused button refuses the dictation")
    func buttonIsNotEditable() {
        let decision = PasteTarget.decide(PasteTarget.Focus(role: "AXButton", valueIsSettable: false))
        #expect(decision == .notEditable("AXButton"))
        #expect(!decision.allowsPaste, "the ⌘V on a button is an arbitrary shortcut")
    }

    @Test("an open menu refuses the dictation")
    func menuItemIsNotEditable() {
        let decision = PasteTarget.decide(PasteTarget.Focus(role: "AXMenuItem", valueIsSettable: false))
        #expect(!decision.allowsPaste)
    }

    /// The false negative this whole design exists to avoid: an application
    /// whose focused element nobody here recognizes still gets the dictation.
    @Test("an unrecognized role does not refuse")
    func unknownRolePastes() {
        let decision = PasteTarget.decide(PasteTarget.Focus(role: "AXWebArea", valueIsSettable: false))
        #expect(decision == .unknown("AXWebArea"))
        #expect(decision.allowsPaste, "an unknown role cannot leave the app mute")
    }

    @Test("an element that does not answer its role does not refuse")
    func missingRolePastes() {
        let decision = PasteTarget.decide(PasteTarget.Focus(role: nil, valueIsSettable: false))
        #expect(decision.allowsPaste)
    }

    /// Failure of the Accessibility call, permission missing, timeout, nothing
    /// focused: they all reach the rule as no element at all.
    @Test("no focused element does not refuse")
    func noElementPastes() {
        let decision = PasteTarget.decide(nil)
        #expect(decision == .unknown("no focused element"))
        #expect(decision.allowsPaste)
    }

    /// The single line the rest of the app reads. Getting this backwards would
    /// invert every case above at once.
    @Test("only a positive refusal stops the paste")
    func onlyNotEditableBlocks() {
        #expect(PasteTarget.Decision.editable("x").allowsPaste)
        #expect(PasteTarget.Decision.unknown("x").allowsPaste)
        #expect(!PasteTarget.Decision.notEditable("x").allowsPaste)
    }

    /// The two lists cannot share a name: a role in both would have its answer
    /// decided by the order of two `if`s, which is not a rule anyone could read.
    @Test("no role is in both lists")
    func listsDoNotOverlap() {
        #expect(PasteTarget.editableRoles.isDisjoint(with: PasteTarget.rolesWithoutText))
    }
}
