import AppKit
import MarkCore

/// ⌘P: a keyboard-only Markdown browser.
/// Opens in the current file's folder (files newest first, then subfolders). Typing fuzzy-filters that folder
/// and searches the whole Mac via Spotlight. ↵ open / enter folder, ⇥ or → enter folder, ⌫ or ← on an empty
/// query (or ⌘↑) goes up, ⌘↓ opens, "~/" jumps home, esc clears then closes.
@MainActor final class QuickOpen: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSWindowDelegate {
    static let shared = QuickOpen()

    private enum Row {
        case header(String)
        case file(URL, FuzzyMatch?, everywhere: Bool)
        case folder(URL, FuzzyMatch?)

        var url: URL? {
            switch self {
            case .header: nil
            case .file(let u, _, _), .folder(let u, _): u
            }
        }
    }

    private let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
                                 styleMask: [.borderless], backing: .buffered, defer: true)
    private let field = NSTextField()
    private let crumb = QuickOpen.label("", 16, Theme.syntax)
    private let table = NSTableView()
    private let status = QuickOpen.label("", 11, Theme.syntax)
    private let empty = QuickOpen.label("Nothing here", 13, Theme.syntax)
    private var folder = URL(fileURLWithPath: NSHomeDirectory())
    private var files: [URL] = [], folders: [URL] = [], spotlight: [URL] = []
    private var rows: [Row] = []
    private var query: NSMetadataQuery?
    private var onOpen: ((URL) -> Void)?
    private static let ago: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    override init() {
        super.init()
        build()
    }

    func show(over window: NSWindow?, folder: URL, onOpen: @escaping (URL) -> Void) {
        self.onOpen = onOpen
        go(to: folder)
        let size = panel.frame.size
        let anchor = window?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY - 96 - size.height))
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    // MARK: Navigation

    private var q: String { field.stringValue.trimmingCharacters(in: .whitespaces) }

    private func go(to dir: URL, selecting child: URL? = nil) {
        folder = dir.standardizedFileURL
        files = markdownFiles(in: folder)
        folders = browsableFolders(in: folder)
        field.stringValue = ""
        let path = displayPath(folder.appendingPathComponent("x"))
        crumb.stringValue = path == "/" ? "/" : path + "/"
        search()
        if let child, let i = rows.firstIndex(where: { $0.url?.standardizedFileURL == child.standardizedFileURL }) { select(i) }
    }

    private func up() {
        guard folder.path != "/" else { return NSSound.beep() }
        go(to: parentFolder(of: folder), selecting: folder)
    }

    private var selected: Row? { rows.indices.contains(table.selectedRow) ? rows[table.selectedRow] : nil }

    /// ↵ / ⌘↓ / double-click.
    @objc private func activate() {
        switch selected {
        case .file(let url, _, _)?:
            close()
            onOpen?(url)
        case .folder(let url, _)?:
            go(to: url)
        default:
            NSSound.beep()
        }
    }

    private func enterSelectedFolder() -> Bool {
        guard case .folder(let url, _)? = selected else { return false }
        go(to: url)
        return true
    }

    // MARK: Search

    func controlTextDidChange(_ obj: Notification) {
        switch field.stringValue {
        case "~/": go(to: FileManager.default.homeDirectoryForCurrentUser)
        case "/": go(to: URL(fileURLWithPath: "/"))
        default: search()
        }
    }

    private func search() {
        query?.stop()
        query = nil
        spotlight = []
        render()
        guard !q.isEmpty else { return }

        let mq = NSMetadataQuery()
        mq.predicate = NSPredicate(format: "(%K LIKE[cd] %@) OR (%K LIKE[cd] %@)",
                                   NSMetadataItemFSNameKey, "*\(q)*.md", NSMetadataItemFSNameKey, "*\(q)*.markdown")
        mq.searchScopes = [NSMetadataQueryLocalComputerScope] // every local volume, incl. external drives
        mq.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        NotificationCenter.default.addObserver(self, selector: #selector(gathered(_:)), name: .NSMetadataQueryDidFinishGathering, object: mq)
        NotificationCenter.default.addObserver(self, selector: #selector(gathered(_:)), name: .NSMetadataQueryDidUpdate, object: mq)
        query = mq
        mq.start()
        status.stringValue = "Searching your Mac…"
    }

    @objc private func gathered(_ note: Notification) {
        guard let mq = note.object as? NSMetadataQuery, mq === query else { return }
        mq.disableUpdates()
        // ponytail: scan the 2000 newest hits, keep 50 after dropping system/app/dependency noise.
        spotlight = (0..<min(mq.resultCount, 2000))
            .compactMap { (mq.result(at: $0) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String }
            .filter { !isNoisePath($0) }
            .prefix(50)
            .map { URL(fileURLWithPath: $0) }
        mq.enableUpdates()
        render()
        status.stringValue = count(rows.filter { $0.url != nil }.count, "result")
    }

    /// Rebuild rows from folder contents + Spotlight hits, keeping the selection on the same item if it's still there.
    private func render() {
        let keep = selected?.url
        rows = []
        if q.isEmpty {
            let fileRows: [Row] = files.map { .file($0, nil, everywhere: false) }
            let folderRows: [Row] = folders.map { .folder($0, nil) }
            rows = fileRows + folderRows
            status.stringValue = [count(files.count, "file"), count(folders.count, "folder")].joined(separator: " · ")
        } else {
            typealias Hit = (url: URL, isFolder: Bool, match: FuzzyMatch)
            let candidates: [(URL, Bool)] = files.map { ($0, false) } + folders.map { ($0, true) }
            let local: [Hit] = candidates
                .compactMap { u, isDir in fuzzyMatch(q, u.lastPathComponent).map { (u, isDir, $0) } }
                .sorted { a, b in
                    a.match.score != b.match.score ? a.match.score > b.match.score
                        : a.url.lastPathComponent.count < b.url.lastPathComponent.count
                }
            if !local.isEmpty {
                rows.append(.header("In " + crumb.stringValue))
                for h in local { rows.append(h.isFolder ? .folder(h.url, h.match) : .file(h.url, h.match, everywhere: false)) }
            }
            let shown = Set(files.map(\.standardizedFileURL))
            let elsewhere = spotlight.filter { !shown.contains($0.standardizedFileURL) }
            if !elsewhere.isEmpty {
                rows.append(.header("Everywhere"))
                rows += elsewhere.map { .file($0, fuzzyMatch(q, $0.lastPathComponent), everywhere: true) }
            }
        }
        table.reloadData()
        empty.isHidden = !rows.isEmpty
        select(rows.firstIndex { keep != nil && $0.url == keep } ?? rows.firstIndex { $0.url != nil })
    }

    private func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    private func select(_ i: Int?) {
        guard let i else { return table.deselectAll(nil) }
        table.selectRowIndexes([i], byExtendingSelection: false)
        table.scrollRowToVisible(i)
    }

    // MARK: Keyboard

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        // Only real key presses navigate. Dictation/accessibility tools insert text by sending these same
        // commands (go to start/end, delete) — treating those as ⌘↑/⌘↓ sent the browser wandering.
        guard NSApp.currentEvent?.type == .keyDown else { return false }
        let atEnd = textView.selectedRange().location == (textView.string as NSString).length
        switch sel {
        case #selector(NSResponder.moveDown(_:)): move(1)
        case #selector(NSResponder.moveUp(_:)): move(-1)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.moveToEndOfDocument(_:)): activate()
        case #selector(NSResponder.insertTab(_:)): if !enterSelectedFolder() { NSSound.beep() }
        case #selector(NSResponder.moveRight(_:)): return atEnd && enterSelectedFolder()
        case #selector(NSResponder.moveLeft(_:)), #selector(NSResponder.deleteBackward(_:)):
            guard field.stringValue.isEmpty else { return false }
            up()
        case #selector(NSResponder.moveToBeginningOfDocument(_:)): up()
        case #selector(NSResponder.cancelOperation(_:)):
            if field.stringValue.isEmpty { close() } else { field.stringValue = ""; search() }
        default: return false
        }
        return true
    }

    private func move(_ delta: Int) {
        var i = table.selectedRow
        repeat { i += delta } while rows.indices.contains(i) && rows[i].url == nil // skip section headers
        if rows.indices.contains(i) { select(i) }
    }

    private func close() {
        query?.stop()
        query = nil
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows[row].url != nil }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SubtleRowView() }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .header: 30
        case .folder: 38
        case .file: 48
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let l = Self.label(title, 11, Theme.syntax)
            l.lineBreakMode = .byTruncatingHead
            return cell([l], icon: nil, trailing: nil, inset: 14)
        case .folder(let url, let match):
            return cell([title(url.lastPathComponent, match)], icon: "folder", trailing: "›")
        case .file(let url, let match, let everywhere):
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let sub = everywhere ? displayPath(url) : modified.map { "Edited " + Self.ago.localizedString(for: $0, relativeTo: Date()) } ?? ""
            let subtitle = Self.label(sub, 12, Theme.syntax)
            subtitle.lineBreakMode = .byTruncatingHead
            return cell([title(url.lastPathComponent, match), subtitle], icon: "doc.text", trailing: nil)
        }
    }

    /// File name with the fuzzy-matched letters in SemiBold.
    private func title(_ name: String, _ match: FuzzyMatch?) -> NSTextField {
        let regular = NSFont(name: "Geist-Regular", size: 14) ?? .systemFont(ofSize: 14)
        let strong = NSFont(name: "Geist-SemiBold", size: 14) ?? .systemFont(ofSize: 14, weight: .semibold)
        let s = NSMutableAttributedString(string: name, attributes: [.font: regular, .foregroundColor: NSColor.labelColor])
        for p in match?.positions ?? [] where p < s.length { s.addAttribute(.font, value: strong, range: NSRange(location: p, length: 1)) }
        let l = NSTextField(labelWithAttributedString: s)
        l.lineBreakMode = .byTruncatingMiddle
        return l
    }

    private func cell(_ lines: [NSView], icon: String?, trailing: String?, inset: CGFloat = 12) -> NSView {
        let text = NSStackView(views: lines)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var views: [NSView] = []
        if let icon, let image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let v = NSImageView(image: image)
            v.contentTintColor = Theme.syntax
            v.symbolConfiguration = .init(pointSize: 14, weight: .regular)
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalToConstant: 20).isActive = true // file and folder glyphs differ in width; keep names aligned
            views.append(v)
        }
        views.append(text)
        if let trailing {
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            views += [spacer, Self.label(trailing, 16, Theme.syntax)]
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        let cell = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: inset),
            row.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
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
        crumb.lineBreakMode = .byTruncatingHead
        crumb.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        crumb.setContentHuggingPriority(.required, for: .horizontal)
        field.placeholderString = "Search or browse…"
        field.font = NSFont(name: "Geist-Regular", size: 16) ?? .systemFont(ofSize: 16)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self

        table.addTableColumn(NSTableColumn(identifier: .init("item")))
        table.headerView = nil
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(activate)
        table.refusesFirstResponder = true // keep typing in the field
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

        let hints = Self.label("↵ open    ⇥ into folder    ⌫ back    esc close", 11, Theme.syntax)
        let top = ColorView(fill: Theme.border), bottom = ColorView(fill: Theme.border)

        for v in [icon, crumb, field, top, scroll, empty, bottom, status, hints] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            crumb.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            crumb.firstBaselineAnchor.constraint(equalTo: field.firstBaselineAnchor),
            crumb.widthAnchor.constraint(lessThanOrEqualTo: card.widthAnchor, multiplier: 0.45),
            field.leadingAnchor.constraint(equalTo: crumb.trailingAnchor, constant: 2),
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
            status.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            status.centerYAnchor.constraint(equalTo: card.bottomAnchor, constant: -17),
            hints.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            hints.centerYAnchor.constraint(equalTo: status.centerYAnchor),
        ])
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
