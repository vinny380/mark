import AppKit

@objc(MarkdownDocument) final class MarkdownDocument: NSDocument {
    private var text = ""
    private(set) var textView: EditorTextView?

    override class var autosavesInPlace: Bool { true }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let s = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        // ponytail: NSDocument calls these on main unless concurrent read/async write is enabled (it isn't).
        MainActor.assumeIsolated {
            text = s
            textView?.setMarkdown(s) // external change / revert
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        MainActor.assumeIsolated { Data((textView?.markdown ?? text).utf8) }
    }

    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = Theme.background
        window.minSize = NSSize(width: 420, height: 300)

        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let tv = EditorTextView(frame: scroll.contentView.bounds)
        tv.autoresizingMask = [.width]
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.setMarkdown(text)
        scroll.documentView = tv
        window.contentView = scroll
        textView = tv

        let controller = NSWindowController(window: window)
        addWindowController(controller)
        window.center()
        window.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }
}
