import AppKit
import MarkCore
import UniformTypeIdentifiers

/// A picture floating in the editor. Clicks pass through to the text.
/// Draws itself (not NSImageView) so offscreen snapshots — the demo renderer — capture it too.
final class ImageOverlay: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { image?.draw(in: bounds) }
}

final class EditorTextView: NSTextView {
    private(set) var isPreview = false
    private var source = "" // the real Markdown while previewing
    /// The document's folder, for relative image paths in Preview (asked fresh: the file may have been renamed or moved).
    private var baseURL: URL? { (window?.windowController?.document as? NSDocument)?.fileURL?.deletingLastPathComponent() }

    /// The document's Markdown, whatever mode the view is in. Save from this, never from `string`.
    var markdown: String { isPreview ? source : string }

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        isRichText = false
        allowsUndo = true
        usesFindBar = true
        drawsBackground = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        insertionPointColor = .labelColor
        typingAttributes = Theme.baseAttributes
        linkTextAttributes = [.underlineStyle: NSUnderlineStyle.single.rawValue, .cursor: NSCursor.pointingHand]
        NotificationCenter.default.addObserver(self, selector: #selector(imageLoaded), name: Images.didLoad, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
        registerForDraggedTypes([.fileURL, .URL, .png, .tiff])
    }

    private var column: CGFloat {
        max(100, min(720, (textContainer?.size.width ?? 720) - 2 * (textContainer?.lineFragmentPadding ?? 0)))
    }

    private func renderPreview() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        textStorage?.setAttributedString(Theme.preview(source, base: baseURL, maxWidth: column, dark: dark) {
            Diagrams.shared.image($0, $1, dark: dark)
        })
        updateImageOverlays()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if isPreview { renderPreview() } // diagrams are drawn for light or dark
    }

    @objc private func imageLoaded() {
        let anchor = scrollFraction
        if isPreview { renderPreview() } else { restyle() }
        scrollFraction = anchor
    }

    // MARK: Images while editing

    private var imageRuns: [(range: NSRange, src: String)] = []

    private func loadedImage(_ src: String) -> NSImage? { imageURL(src, base: baseURL).flatMap(Images.image) }

    /// Floats each loaded image in the room its line reserved (Theme.apply), so you see it while you write.
    /// The text itself never changes, so what's saved is exactly what you typed.
    private func updateImageOverlays() {
        subviews.filter { $0 is ImageOverlay }.forEach { $0.removeFromSuperview() }
        guard !isPreview, let tlm = textLayoutManager, let content = tlm.textContentManager else { return }
        for run in imageRuns {
            guard let image = loadedImage(run.src),
                  let loc = content.location(content.documentRange.location, offsetBy: run.range.location) else { continue }
            tlm.ensureLayout(for: NSTextRange(location: loc))
            // last line with text: a paragraph that ends the document also carries an empty "extra" line after its spacing
            guard let fragment = tlm.textLayoutFragment(for: loc),
                  let line = fragment.textLineFragments.last(where: { $0.characterRange.length > 0 }) else { continue }
            let size = Theme.fit(image.size, column)
            let y = textContainerOrigin.y + fragment.layoutFragmentFrame.minY + line.typographicBounds.maxY + Theme.imageGap
            let x = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0)
            let view = ImageOverlay(frame: NSRect(x: x, y: y, width: size.width, height: size.height))
            view.image = Theme.rounded(image, size)
            addSubview(view)
        }
    }

    // MARK: Drag & paste images

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let op = super.draggingEntered(sender)
        return !isPreview && Self.hasImage(sender.draggingPasteboard) ? .copy : op
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let op = super.draggingUpdated(sender)
        return !isPreview && Self.hasImage(sender.draggingPasteboard) ? .copy : op
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let at = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        if insertImages(from: sender.draggingPasteboard, at: at) {
            window?.makeFirstResponder(self)
            return true
        }
        return super.performDragOperation(sender)
    }

    private static let imageTypes = NSImage.imageTypes

    private static func imageFiles(_ pb: NSPasteboard) -> [URL] {
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
    }

    /// A dragged web image: an http(s) URL that is an image file, or comes with image data (browsers send both).
    private static func webImage(_ pb: NSPasteboard) -> URL? {
        guard let url = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.first,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let looksLikeImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
        return looksLikeImage || pb.availableType(from: [.png, .tiff]) != nil ? url : nil
    }

    private static func hasImage(_ pb: NSPasteboard) -> Bool {
        !imageFiles(pb).isEmpty || webImage(pb) != nil || pb.availableType(from: [.png, .tiff]) != nil
    }

    /// Drop/paste: image files → copied into ./assets (or linked if already beside the note), web images →
    /// linked by URL, raw image data (screenshots) → saved as PNG in ./assets. Returns false if there's no image.
    @discardableResult
    func insertImages(from pb: NSPasteboard, at index: Int) -> Bool {
        guard isEditable else { return false }
        var lines: [String] = []
        let files = Self.imageFiles(pb)
        if !files.isEmpty {
            lines = files.compactMap(importImageFile)
        } else if let url = Self.webImage(pb) {
            lines = [imageMarkdown(alt: url.deletingPathExtension().lastPathComponent, path: url.absoluteString)]
        } else if pb.string(forType: .string) == nil, let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
                  let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]),
                  let path = saveAsset(png) {
            lines = [imageMarkdown(alt: "Pasted image", path: path)]
        }
        guard !lines.isEmpty else { return false }
        let block = lines.joined(separator: "\n")
        return edit { text, _ in insertBlock(text, at: min(index, (text as NSString).length), block) }
    }

    private var assetsFolder: URL? { baseURL?.appendingPathComponent("assets", isDirectory: true) }

    private func importImageFile(_ file: URL) -> String? {
        let alt = file.deletingPathExtension().lastPathComponent
        guard let base = baseURL else { return imageMarkdown(alt: alt, path: file.path) }
        if let rel = relativePath(of: file, inside: base) { return imageMarkdown(alt: alt, path: rel) }
        guard let assets = assetsFolder,
              (try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)) != nil else {
            return imageMarkdown(alt: alt, path: file.path)
        }
        let name = assetName(for: file.lastPathComponent) { FileManager.default.fileExists(atPath: assets.appendingPathComponent($0).path) }
        do {
            try FileManager.default.copyItem(at: file, to: assets.appendingPathComponent(name))
            return imageMarkdown(alt: alt, path: "assets/" + name)
        } catch {
            return imageMarkdown(alt: alt, path: file.path) // can't copy: link the original
        }
    }

    private func saveAsset(_ png: Data) -> String? {
        guard let assets = assetsFolder,
              (try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)) != nil else { return nil }
        let stamp = Self.stamp.string(from: Date())
        let name = assetName(for: "pasted-\(stamp).png") { FileManager.default.fileExists(atPath: assets.appendingPathComponent($0).path) }
        guard (try? png.write(to: assets.appendingPathComponent(name), options: .withoutOverwriting)) != nil else { return nil }
        return "assets/" + name
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()

    override convenience init(frame: NSRect) {
        let container = NSTextContainer(size: NSSize(width: frame.width, height: .greatestFiniteMagnitude))
        let layout = NSTextLayoutManager()
        layout.textContainer = container
        NSTextContentStorage().addTextLayoutManager(layout)
        self.init(frame: frame, textContainer: container)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setMarkdown(_ s: String) {
        if isPreview {
            source = s
            renderPreview()
        } else {
            string = s
            restyle()
        }
    }

    /// ⌘E: hide/show the Markdown symbols. Preview is read-only; the source is untouched.
    @objc func togglePreview(_ sender: Any?) {
        let anchor = scrollFraction
        if isPreview {
            isPreview = false
            string = source
            restyle()
        } else {
            source = string
            isPreview = true
            renderPreview()
            setSelectedRange(NSRange(location: 0, length: 0))
        }
        isEditable = !isPreview
        window?.subtitle = isPreview ? "Preview" : ""
        scrollFraction = anchor
    }

    // ponytail: keeps the same relative scroll position across ⌘E; anchor to the first visible line if it drifts on long docs.
    private var scrollFraction: CGFloat {
        get {
            guard let clip = enclosingScrollView?.contentView, frame.height > clip.bounds.height else { return 0 }
            return clip.bounds.minY / (frame.height - clip.bounds.height)
        }
        set {
            guard let clip = enclosingScrollView?.contentView else { return }
            layoutSubtreeIfNeeded()
            clip.scroll(to: NSPoint(x: 0, y: max(0, newValue * (frame.height - clip.bounds.height))))
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
    }

    // Undo history belongs to the source text; replaying it onto the preview text would corrupt the document.
    @objc func undo(_ sender: Any?) { if !isPreview { undoManager?.undo() } }
    @objc func redo(_ sender: Any?) { if !isPreview { undoManager?.redo() } }

    private static let formatting: Set<Selector> = [
        #selector(toggleBold(_:)), #selector(toggleItalic(_:)), #selector(toggleStrikethrough(_:)),
        #selector(toggleInlineCode(_:)), #selector(insertLink(_:)), #selector(setHeadingLevel(_:)), #selector(toggleTodoItem(_:)),
        #selector(moveLineUp(_:)), #selector(moveLineDown(_:)),
    ]

    /// nil = not ours, let AppKit decide.
    private func validate(_ action: Selector?, _ item: Any) -> Bool? {
        switch action {
        case #selector(togglePreview(_:)):
            (item as? NSMenuItem)?.state = isPreview ? .on : .off
            return true
        case #selector(undo(_:)): return !isPreview && undoManager?.canUndo == true
        case #selector(redo(_:)): return !isPreview && undoManager?.canRedo == true
        case let a? where Self.formatting.contains(a): return !isPreview
        default: return nil
        }
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        validate(item.action, item) ?? super.validateUserInterfaceItem(item)
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        validate(item.action, item) ?? super.validateMenuItem(item)
    }

    // MARK: Formatting shortcuts (pure edits live in MarkCore/Editing.swift)

    @objc func toggleBold(_ sender: Any?) { edit { toggleWrap($0, $1, "**") } }
    @objc func toggleItalic(_ sender: Any?) { edit { toggleWrap($0, $1, "*") } }
    @objc func toggleStrikethrough(_ sender: Any?) { edit { toggleWrap($0, $1, "~~") } }
    @objc func toggleInlineCode(_ sender: Any?) { edit { toggleWrap($0, $1, "`") } }
    @objc func insertLink(_ sender: Any?) { edit(makeLink) }
    @objc func toggleTodoItem(_ sender: Any?) { edit(toggleTodo) }
    @objc func moveLineUp(_ sender: Any?) { edit { moveLines($0, $1, up: true) } }
    @objc func moveLineDown(_ sender: Any?) { edit { moveLines($0, $1, up: false) } }

    /// Text size changed (⌘+/⌘−/⌘0): redraw with the new sizes.
    @objc func themeChanged() {
        typingAttributes = Theme.baseAttributes
        if isPreview { renderPreview() } else { restyle() }
    }
    /// Menu item tag = heading level (0 = plain text).
    @objc func setHeadingLevel(_ sender: Any?) {
        let level = (sender as? NSMenuItem)?.tag ?? 0
        edit { setHeading($0, $1, level: level) }
    }

    override func insertNewline(_ sender: Any?) {
        if !edit(continueList) { super.insertNewline(sender) }
    }
    override func insertTab(_ sender: Any?) {
        if !edit({ indentList($0, $1, outdent: false) }) { super.insertTab(sender) }
    }
    override func insertBacktab(_ sender: Any?) {
        if !edit({ indentList($0, $1, outdent: true) }) { super.insertBacktab(sender) }
    }
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let pasted = pb.string(forType: .string) ?? ""
        if edit({ linkPaste($0, $1, pasted) }) { return }
        if selectedRange().length == 0, insertImages(from: pb, at: selectedRange().location) { return }
        super.paste(sender)
    }

    /// Applies an edit as one undoable change. Returns false when there's nothing to do (caller falls back).
    @discardableResult
    private func edit(_ make: (String, NSRange) -> TextEdit?) -> Bool {
        guard isEditable, !hasMarkedText(), let e = make(string, selectedRange()),
              shouldChangeText(in: e.range, replacementString: e.replacement) else { return false }
        textStorage?.replaceCharacters(in: e.range, with: e.replacement)
        didChangeText()
        setSelectedRange(e.selection)
        return true
    }

    /// Centers a max-720pt text column.
    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        let inset = NSSize(width: max(48, (size.width - 720) / 2), height: 56)
        if textContainerInset != inset {
            textContainerInset = inset
            if !isPreview, !imageRuns.isEmpty { restyle() } // images resize with the column
        }
    }

    override func didChangeText() {
        super.didChangeText()
        restyle()
    }

    // ponytail: full restyle per keystroke; restyle only the edited paragraph if >200KB files feel slow.
    private func restyle() {
        guard !isPreview, !hasMarkedText(), let storage = textStorage else { return } // don't disturb IME composition
        let runs = MarkdownStyler.runs(in: string)
        imageRuns = runs.compactMap { if case .image(let src) = $0.style { ($0.range, src) } else { nil } }
        Theme.apply(runs, to: storage) { [column] src in
            self.loadedImage(src).map { Theme.fit($0.size, column) }
        }
        typingAttributes = Theme.baseAttributes
        updateImageOverlays()
    }
}
