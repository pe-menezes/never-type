import AppKit
import FalaFlowCore

/// A janela de vocabulário.
///
/// É a primeira janela do app, que até aqui vivia só na menu bar. Um app
/// acessório pode ter janela sem virar app de Dock — o que muda é que ele
/// precisa se ativar antes de mostrar, senão a janela aparece sem foco e o
/// teclado não chega nela.
///
/// Duas abas porque são duas coisas diferentes: termo é dica para o modelo,
/// substituição é troca literal depois. Ver `Vocabulary`.
@MainActor
final class VocabularyWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let vocabulary: Vocabulary
    private var window: NSWindow?
    private var termsTable: NSTableView!
    private var replacementsTable: NSTableView!

    /// Cópias de trabalho: a tabela edita estas, e o disco só é tocado ao salvar.
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
        // Ativar antes de mostrar: sem isto a janela de um app acessório abre
        // atrás do que estiver na frente e não recebe teclado.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    // MARK: - Construção

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "FalaFlow · Vocabulário"
        window.delegate = self
        window.isReleasedWhenClosed = false

        let tabs = NSTabView(frame: NSRect(x: 12, y: 12, width: 436, height: 356))
        tabs.autoresizingMask = [.width, .height]

        let (termsTab, termsTable) = makeTab(
            title: "Vocabulário",
            columns: [("termo", "Termo que o modelo deve esperar", 380)],
            hint: "Enviesa o modelo a ouvir estas palavras. Não garante nada, mas também não estraga nada — use para palavra que às vezes é legítima.")
        self.termsTable = termsTable

        let (replacementsTab, replacementsTable) = makeTab(
            title: "Substituições",
            columns: [("de", "Saiu", 180), ("para", "Deveria ser", 180)],
            hint: "Troca literal, SEMPRE. Só para o que nunca é certo (vibe flow → vibeflow). Palavra que às vezes é legítima: use a frase inteira, ou a aba Vocabulário.")
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
        id?.rawValue == "Vocabulário"
    }

    // MARK: - Dados

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
        // O row e a coluna viajam no próprio campo: sem isto, descobrir qual
        // célula foi editada dependeria de perguntar à tabela onde está o foco,
        // que já mudou quando a ação chega.
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

    // MARK: - Ações

    @objc private func commitEdit(_ sender: NSTextField) {
        let parts = (sender.identifier?.rawValue ?? "").split(separator: "|", maxSplits: 1)
        guard let table = parts.first.map(String.init) else { return }
        let column = parts.count > 1 ? String(parts[1]) : ""
        let row = sender.tag

        if table == "Vocabulário" {
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

    /// Salva a cada edição, e não num botão "Salvar".
    ///
    /// A janela pode ser fechada de várias formas — botão, ⌘W, encerrar o app —
    /// e um botão de salvar transformaria cada uma delas numa chance de perder
    /// o que foi digitado.
    private func persist() {
        vocabulary.setTerms(terms)
        vocabulary.setReplacements(replacements)
    }

    func windowWillClose(_ notification: Notification) {
        persist()
        // Devolve o foco: um app acessório que fica ativo depois de fechar a
        // janela deixa a pessoa sem saber para onde o teclado vai.
        NSApp.hide(nil)
    }
}
