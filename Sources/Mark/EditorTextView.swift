import AppKit
import MarkCore

final class EditorTextView: NSTextView {
    private(set) var isPreview = false
    private var source = "" // the real Markdown while previewing

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
    }

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
            textStorage?.setAttributedString(Theme.preview(s))
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
            textStorage?.setAttributedString(Theme.preview(source))
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
        let pasted = NSPasteboard.general.string(forType: .string) ?? ""
        if !edit({ linkPaste($0, $1, pasted) }) { super.paste(sender) }
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
        if textContainerInset != inset { textContainerInset = inset }
    }

    override func didChangeText() {
        super.didChangeText()
        restyle()
    }

    // ponytail: full restyle per keystroke; restyle only the edited paragraph if >200KB files feel slow.
    private func restyle() {
        guard !isPreview, !hasMarkedText(), let storage = textStorage else { return } // don't disturb IME composition
        Theme.apply(MarkdownStyler.runs(in: string), to: storage)
        typingAttributes = Theme.baseAttributes
    }
}
