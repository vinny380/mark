import AppKit
import MarkCore

/// ⌘K palette. Empty query: Markdown files in the current folder. Typing: Spotlight search of the whole Mac.
@MainActor final class QuickOpen: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSWindowDelegate {
    static let shared = QuickOpen()

    private let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
                                 styleMask: [.borderless], backing: .buffered, defer: true)
    private let field = NSTextField()
    private let table = NSTableView()
    private let caption = QuickOpen.label("", 11, Theme.syntax)
    private let empty = QuickOpen.label("No Markdown files", 13, Theme.syntax)
    private var nearby: [URL] = []
    private var results: [URL] = [] { didSet { table.reloadData(); empty.isHidden = !results.isEmpty } }
    private var folder = URL(fileURLWithPath: NSHomeDirectory())
    private var query: NSMetadataQuery?
    private var onOpen: ((URL) -> Void)?

    override init() {
        super.init()
        build()
    }

    func show(over window: NSWindow?, folder: URL, onOpen: @escaping (URL) -> Void) {
        self.onOpen = onOpen
        self.folder = folder
        nearby = markdownFiles(in: folder)
        field.stringValue = ""
        search("")
        let size = panel.frame.size
        let anchor = window?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY - 96 - size.height))
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    // MARK: Search

    func controlTextDidChange(_ obj: Notification) { search(field.stringValue) }

    private func search(_ raw: String) {
        query?.stop()
        query = nil
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            caption.stringValue = displayPath(folder.appendingPathComponent("x"))
            return setResults(nearby)
        }
        caption.stringValue = "Searching your Mac"
        setResults(nearby.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(q) }) // instant, before Spotlight answers

        let mq = NSMetadataQuery()
        mq.predicate = NSPredicate(format: "(%K LIKE[cd] %@) OR (%K LIKE[cd] %@)",
                                   NSMetadataItemFSNameKey, "*\(q)*.md", NSMetadataItemFSNameKey, "*\(q)*.markdown")
        mq.searchScopes = [NSMetadataQueryLocalComputerScope] // every local volume, incl. external drives
        mq.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        NotificationCenter.default.addObserver(self, selector: #selector(gathered(_:)), name: .NSMetadataQueryDidFinishGathering, object: mq)
        NotificationCenter.default.addObserver(self, selector: #selector(gathered(_:)), name: .NSMetadataQueryDidUpdate, object: mq)
        query = mq
        mq.start()
    }

    @objc private func gathered(_ note: Notification) {
        guard let mq = note.object as? NSMetadataQuery, mq === query else { return }
        mq.disableUpdates()
        // ponytail: scan the 2000 newest hits, keep 50 after dropping node_modules/caches; widen if real notes get crowded out.
        let found = (0..<min(mq.resultCount, 2000))
            .compactMap { (mq.result(at: $0) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String }
            .filter { !isNoisePath($0) }
            .prefix(50)
            .map { URL(fileURLWithPath: $0) }
        mq.enableUpdates()
        let q = field.stringValue.trimmingCharacters(in: .whitespaces)
        let local = nearby.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(q) }
        setResults(local + found.filter { !local.contains($0) })
        caption.stringValue = "\(results.count) on your Mac"
    }

    private func setResults(_ urls: [URL]) {
        results = urls
        if !urls.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false); table.scrollRowToVisible(0) }
    }

    // MARK: Keyboard

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)): move(1)
        case #selector(NSResponder.moveUp(_:)): move(-1)
        case #selector(NSResponder.insertNewline(_:)): openSelected()
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        let row = min(max(table.selectedRow + delta, 0), results.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func openSelected() {
        guard results.indices.contains(table.selectedRow) else { return }
        let url = results[table.selectedRow]
        close()
        onOpen?(url)
    }

    private func close() {
        query?.stop()
        query = nil
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SubtleRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let url = results[row]
        let name = Self.label(url.lastPathComponent, 14, .labelColor)
        let path = Self.label(displayPath(url), 12, Theme.syntax)
        name.lineBreakMode = .byTruncatingMiddle
        path.lineBreakMode = .byTruncatingHead
        let stack = NSStackView(views: [name, path])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        let cell = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: Layout

    private func build() {
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true

        let card = ColorView(fill: Theme.background, border: Theme.border, radius: 12)
        panel.contentView = card

        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        icon.contentTintColor = Theme.syntax
        field.placeholderString = "Search Markdown files…"
        field.font = NSFont(name: "Geist-Regular", size: 16) ?? .systemFont(ofSize: 16)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self

        let column = NSTableColumn(identifier: .init("file"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 48
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.refusesFirstResponder = true // keep typing in the field
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

        let hints = Self.label("↑↓ navigate    ↵ open    esc close", 11, Theme.syntax)
        let top = ColorView(fill: Theme.border), bottom = ColorView(fill: Theme.border)

        for v in [icon, field, top, scroll, empty, bottom, caption, hints] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            field.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            top.topAnchor.constraint(equalTo: card.topAnchor, constant: 56),
            top.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            top.heightAnchor.constraint(equalToConstant: 1),
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            bottom.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 1),
            bottom.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -34),
            caption.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            caption.centerYAnchor.constraint(equalTo: card.bottomAnchor, constant: -17),
            caption.trailingAnchor.constraint(lessThanOrEqualTo: hints.leadingAnchor, constant: -12),
            hints.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            hints.centerYAnchor.constraint(equalTo: caption.centerYAnchor),
        ])
        caption.lineBreakMode = .byTruncatingHead
        caption.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private static func label(_ s: String, _ size: CGFloat, _ color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = NSFont(name: "Geist-Regular", size: size) ?? .systemFont(ofSize: size)
        l.textColor = color
        return l
    }
}

/// Borderless panels can't become key by default; this one needs the text field.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Solid fill + hairline border that follow light/dark (layer colors don't update on their own).
private final class ColorView: NSView {
    private let fill: NSColor, border: NSColor?, radius: CGFloat
    init(fill: NSColor, border: NSColor? = nil, radius: CGFloat = 0) {
        self.fill = fill; self.border = border; self.radius = radius
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fill.cgColor
            layer?.borderColor = border?.cgColor
            layer?.borderWidth = border == nil ? 0 : 1
            layer?.cornerRadius = radius
            layer?.masksToBounds = radius > 0
        }
    }
}

/// Selected row: soft gray rounded rect instead of the system accent color.
private final class SubtleRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        Theme.codeBackground.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 8, yRadius: 8).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal } // keep text colors on selection
}
