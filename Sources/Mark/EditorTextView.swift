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

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(togglePreview(_:)):
            (item as? NSMenuItem)?.state = isPreview ? .on : .off
            return true
        case #selector(undo(_:)): return !isPreview && undoManager?.canUndo == true
        case #selector(redo(_:)): return !isPreview && undoManager?.canRedo == true
        default: return super.validateUserInterfaceItem(item)
        }
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
