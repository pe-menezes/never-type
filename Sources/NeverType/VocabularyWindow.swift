import AppKit
import NeverTypeCore

/// The vocabulary window.
///
/// It is the app's first window; until here it lived only in the menu bar. An
/// accessory app can have a window without becoming a Dock app — what changes is
/// that it needs to activate before showing, otherwise the window appears without
/// focus and the keyboard does not reach it.
///
/// Two tabs because they are two different things: a term is a hint to the
/// model, a replacement is a literal swap afterwards. See `Vocabulary`.
@MainActor
final class VocabularyWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let vocabulary: Vocabulary
    private var window: NSWindow?
    private var termsTable: NSTableView!
    private var replacementsTable: NSTableView!

    /// Working copies: the table edits these, and the disk is only touched on save.
    private var terms: [String] = []
    private var replacements: [Replacement] = []

    init(vocabulary: Vocabulary) {
        self.vocabulary = vocabulary
        super.init()
    }

    func show() {
        terms = vocabulary.terms
        replacements = vocabulary.replacements

        let window = self.window ?? makeWindow()
        self.window = window
        termsTable.reloadData()
        replacementsTable.reloadData()
        // Activate before showing: without this the window of an accessory app
        // opens behind whatever is in front and gets no keyboard.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    // MARK: - Building

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "NeverType · Vocabulary"
        window.delegate = self
        window.isReleasedWhenClosed = false

        let tabs = NSTabView(frame: NSRect(x: 12, y: 12, width: 436, height: 356))
        tabs.autoresizingMask = [.width, .height]

        let (termsTab, termsTable) = makeTab(
            title: "Vocabulary",
            columns: [("termo", "Term the model should expect", 380)],
            hint: "Nudges the model toward hearing these words. Guarantees nothing, breaks nothing — use it for a word that is sometimes legitimate.")
        self.termsTable = termsTable

        let (replacementsTab, replacementsTable) = makeTab(
            title: "Replacements",
            columns: [("de", "Came out as", 180), ("para", "Should be", 180)],
            hint: "Literal replacement, ALWAYS. Only for what is never right (vibe flow → vibeflow). For a word that is sometimes legitimate, use the whole phrase, or the Vocabulary tab.")
        self.replacementsTable = replacementsTable

        tabs.addTabViewItem(termsTab)
        tabs.addTabViewItem(replacementsTab)
        window.contentView?.addSubview(tabs)
        return window
    }

    private func makeTab(title: String,
                         columns: [(id: String, header: String, width: CGFloat)],
                         hint: String) -> (NSTabViewItem, NSTableView) {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))

        let label = NSTextField(labelWithString: hint)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 4, y: 276, width: 412, height: 40)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        label.autoresizingMask = [.width, .minYMargin]
        view.addSubview(label)

        let table = NSTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        table.dataSource = self
        table.delegate = self
        table.identifier = NSUserInterfaceItemIdentifier(title)
        for column in columns {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
            c.title = column.header
            c.width = column.width
            table.addTableColumn(c)
        }

        let scroll = NSScrollView(frame: NSRect(x: 4, y: 40, width: 412, height: 230))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autoresizingMask = [.width, .height]
        view.addSubview(scroll)

        let add = NSButton(title: "+", target: self, action: #selector(addRow(_:)))
        add.bezelStyle = .rounded
        add.frame = NSRect(x: 4, y: 8, width: 34, height: 24)
        add.identifier = NSUserInterfaceItemIdentifier(title)
        view.addSubview(add)

        let remove = NSButton(title: "–", target: self, action: #selector(removeRow(_:)))
        remove.bezelStyle = .rounded
        remove.frame = NSRect(x: 42, y: 8, width: 34, height: 24)
        remove.identifier = NSUserInterfaceItemIdentifier(title)
        view.addSubview(remove)

        item.view = view
        return (item, table)
    }

    private func isTerms(_ id: NSUserInterfaceItemIdentifier?) -> Bool {
        id?.rawValue == "Vocabulary"
    }

    // MARK: - Data

    func numberOfRows(in tableView: NSTableView) -> Int {
        isTerms(tableView.identifier) ? terms.count : replacements.count
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let field = NSTextField(string: value(for: tableView, column: tableColumn, row: row))
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 12)
        field.target = self
        field.action = #selector(commitEdit(_:))
        // The row and the column travel in the field itself: without this,
        // finding out which cell was edited would depend on asking the table
        // where the focus is, which has already moved by the time the action arrives.
        field.tag = row
        field.identifier = NSUserInterfaceItemIdentifier(
            "\(tableView.identifier?.rawValue ?? "")|\(tableColumn?.identifier.rawValue ?? "")")
        return field
    }

    private func value(for tableView: NSTableView, column: NSTableColumn?, row: Int) -> String {
        if isTerms(tableView.identifier) {
            return terms.indices.contains(row) ? terms[row] : ""
        }
        guard replacements.indices.contains(row) else { return "" }
        return column?.identifier.rawValue == "de" ? replacements[row].from : replacements[row].to
    }

    // MARK: - Actions

    @objc private func commitEdit(_ sender: NSTextField) {
        let parts = (sender.identifier?.rawValue ?? "").split(separator: "|", maxSplits: 1)
        guard let table = parts.first.map(String.init) else { return }
        let column = parts.count > 1 ? String(parts[1]) : ""
        let row = sender.tag

        if table == "Vocabulary" {
            guard terms.indices.contains(row) else { return }
            terms[row] = sender.stringValue
        } else {
            guard replacements.indices.contains(row) else { return }
            if column == "de" { replacements[row].from = sender.stringValue }
            else { replacements[row].to = sender.stringValue }
        }
        persist()
    }

    @objc private func addRow(_ sender: NSButton) {
        if isTerms(sender.identifier) {
            terms.append("")
            termsTable.reloadData()
            edit(termsTable, row: terms.count - 1)
        } else {
            replacements.append(Replacement(from: "", to: ""))
            replacementsTable.reloadData()
            edit(replacementsTable, row: replacements.count - 1)
        }
    }

    @objc private func removeRow(_ sender: NSButton) {
        let table = isTerms(sender.identifier) ? termsTable! : replacementsTable!
        let row = table.selectedRow
        guard row >= 0 else { return }
        if isTerms(sender.identifier) {
            guard terms.indices.contains(row) else { return }
            terms.remove(at: row)
        } else {
            guard replacements.indices.contains(row) else { return }
            replacements.remove(at: row)
        }
        table.reloadData()
        persist()
    }

    private func edit(_ table: NSTableView, row: Int) {
        guard row >= 0 else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.editColumn(0, row: row, with: nil, select: true)
    }

    /// Saves on every edit, not on a "Save" button.
    ///
    /// The window can be closed in several ways — button, ⌘W, quitting the app —
    /// and a save button would turn each of them into a chance to lose what was
    /// typed.
    private func persist() {
        vocabulary.setTerms(terms)
        vocabulary.setReplacements(replacements)
    }

    func windowWillClose(_ notification: Notification) {
        persist()
        // Give the focus back: an accessory app that stays active after closing
        // its window leaves the user not knowing where the keyboard goes.
        NSApp.hide(nil)
    }
}
