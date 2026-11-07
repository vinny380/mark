import AppKit
import MarkCore

final class EditorTextView: NSTextView {
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
        string = s
        restyle()
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
        guard !hasMarkedText(), let storage = textStorage else { return } // don't disturb IME composition
        Theme.apply(MarkdownStyler.runs(in: string), to: storage)
        typingAttributes = Theme.baseAttributes
    }
}
