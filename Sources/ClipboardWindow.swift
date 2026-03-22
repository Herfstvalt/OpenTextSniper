import Cocoa

// MARK: - Floating Panel (borderless but accepts keyboard input)

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Clipboard History Window

class ClipboardWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    static let shared = ClipboardWindowController()

    private var panel: FloatingPanel?
    private var searchField: NSTextField!
    private var tableView: NSTableView!
    private var emptyLabel: NSTextField!
    private var countLabel: NSTextField!
    private var filteredEntries: [ClipboardHistory.Entry] = []

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        if panel == nil { setup() }

        filteredEntries = ClipboardHistory.shared.entries
        searchField.stringValue = ""
        tableView.reloadData()
        updateEmptyState()
        updateCount()

        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeFirstResponder(searchField)

        if filteredEntries.count > 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Setup

    private func setup() {
        let width: CGFloat = 520
        let height: CGFloat = 420

        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel?.title = "Clipboard History"
        panel?.titlebarAppearsTransparent = true
        panel?.titleVisibility = .hidden
        panel?.level = .floating
        panel?.backgroundColor = .clear
        panel?.isOpaque = false
        panel?.hasShadow = true
        panel?.isMovableByWindowBackground = true

        // Vibrancy background
        let vibrancy = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        vibrancy.material = .hudWindow
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 12
        vibrancy.layer?.masksToBounds = true
        vibrancy.autoresizingMask = [.width, .height]
        panel?.contentView = vibrancy

        // Search field
        searchField = NSTextField(frame: NSRect(x: 16, y: height - 68, width: width - 32, height: 36))
        searchField.placeholderString = "Search clipboard history..."
        searchField.font = .systemFont(ofSize: 16)
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.autoresizingMask = [.width, .minYMargin]
        vibrancy.addSubview(searchField)

        // Separator
        let sep = NSBox(frame: NSRect(x: 0, y: height - 76, width: width, height: 1))
        sep.boxType = .separator
        sep.autoresizingMask = [.width, .minYMargin]
        vibrancy.addSubview(sep)

        // Scroll + table
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 28, width: width, height: height - 104))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay

        tableView = NSTableView()
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(copySelectedEntry)
        tableView.target = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        column.width = width
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        vibrancy.addSubview(scrollView)

        // Empty state
        emptyLabel = NSTextField(labelWithString: "No captures yet")
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.frame = NSRect(x: 0, y: height / 2 - 30, width: width, height: 20)
        emptyLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        emptyLabel.isHidden = true
        vibrancy.addSubview(emptyLabel)

        // Count label at bottom
        countLabel = NSTextField(labelWithString: "")
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .center
        countLabel.frame = NSRect(x: 0, y: 6, width: width, height: 16)
        countLabel.autoresizingMask = [.width, .maxYMargin]
        vibrancy.addSubview(countLabel)
    }

    private func updateEmptyState() {
        emptyLabel?.isHidden = !filteredEntries.isEmpty
        if !filteredEntries.isEmpty { return }
        emptyLabel?.stringValue = searchField.stringValue.isEmpty
            ? "No captures yet" : "No matches"
    }

    private func updateCount() {
        let total = ClipboardHistory.shared.entries.count
        if filteredEntries.count == total {
            countLabel?.stringValue = "\(total) item\(total == 1 ? "" : "s")"
        } else {
            countLabel?.stringValue = "\(filteredEntries.count) of \(total)"
        }
    }

    // MARK: - Fuzzy Search

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue.lowercased()
        if query.isEmpty {
            filteredEntries = ClipboardHistory.shared.entries
        } else {
            filteredEntries = ClipboardHistory.shared.entries
                .map { ($0, fuzzyScore(query: query, target: $0.text.lowercased())) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
        }
        tableView.reloadData()
        updateEmptyState()
        updateCount()

        if filteredEntries.count > 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func fuzzyScore(query: String, target: String) -> Int {
        var score = 0
        var qi = query.startIndex
        var ti = target.startIndex
        var consecutive = 0
        var firstMatch = true

        while qi < query.endIndex && ti < target.endIndex {
            if query[qi] == target[ti] {
                score += 1 + consecutive * 2
                if firstMatch && ti == target.startIndex {
                    score += 5 // bonus for matching at start
                }
                consecutive += 1
                firstMatch = false
                qi = query.index(after: qi)
            } else {
                consecutive = 0
            }
            ti = target.index(after: ti)
        }

        // All query chars must be matched
        return qi == query.endIndex ? score : 0
    }

    // MARK: - Keyboard Navigation

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.moveDown(_:)) {
            let next = min(tableView.selectedRow + 1, tableView.numberOfRows - 1)
            tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            tableView.scrollRowToVisible(next)
            return true
        }
        if sel == #selector(NSResponder.moveUp(_:)) {
            let prev = max(tableView.selectedRow - 1, 0)
            tableView.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
            tableView.scrollRowToVisible(prev)
            return true
        }
        if sel == #selector(NSResponder.insertNewline(_:)) {
            copySelectedEntry()
            return true
        }
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            hide()
            return true
        }
        return false
    }

    // MARK: - Table View Data Source

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filteredEntries[row]
        let cellWidth = tableColumn?.width ?? 500

        let cell = NSTableCellView()

        // Text preview
        let preview = entry.text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)
        let textField = NSTextField(labelWithString: preview)
        textField.font = .systemFont(ofSize: 13)
        textField.textColor = .labelColor
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.frame = NSRect(x: 16, y: 14, width: cellWidth - 100, height: 20)
        textField.autoresizingMask = [.width]
        cell.addSubview(textField)

        // Timestamp
        let timeField = NSTextField(labelWithString: entry.relativeTime)
        timeField.font = .systemFont(ofSize: 11)
        timeField.textColor = .tertiaryLabelColor
        timeField.alignment = .right
        timeField.frame = NSRect(x: cellWidth - 80, y: 16, width: 64, height: 14)
        timeField.autoresizingMask = [.minXMargin]
        cell.addSubview(timeField)

        // Character count
        let charCount = "\(entry.text.count) chars"
        let countField = NSTextField(labelWithString: charCount)
        countField.font = .systemFont(ofSize: 10)
        countField.textColor = .quaternaryLabelColor
        countField.frame = NSRect(x: 16, y: 2, width: 100, height: 12)
        cell.addSubview(countField)

        return cell
    }

    // MARK: - Copy

    @objc func copySelectedEntry() {
        let row = tableView.selectedRow
        guard row >= 0, filteredEntries.indices.contains(row) else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(filteredEntries[row].text, forType: .string)
        NSSound(named: "Tink")?.play()
        hide()
    }
}
