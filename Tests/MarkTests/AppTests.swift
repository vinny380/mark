import AppKit
import Testing
@testable import Mark

@Test func dynamicColorsResolveOffMainThread() async {
    let colors = await [Theme.background, Theme.codeBackground]
    await Task.detached {
        for c in colors { _ = c.cgColor } // AppKit may resolve dynamic colors off main; must not trap
    }.value
}

@MainActor @Test func fileMenuHasSave() {
    let file = makeMainMenu().item(withTitle: "File")!.submenu!
    let save = file.items.first { $0.action == #selector(NSDocument.save(_:)) }
    #expect(save?.keyEquivalent == "s")
}

@MainActor @Test func previewHidesSymbolsAndRestoresSource() {
    let tv = EditorTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    tv.setMarkdown("# Hi **x**\n- a")
    tv.togglePreview(nil)
    #expect(tv.isPreview)
    #expect(tv.string == "Hi x\n• a")
    #expect(tv.markdown == "# Hi **x**\n- a")
    #expect(!tv.isEditable)
    tv.togglePreview(nil)
    #expect(!tv.isPreview)
    #expect(tv.string == "# Hi **x**\n- a")
    #expect(tv.isEditable)
}

@MainActor @Test func savingDuringPreviewWritesTheMarkdownSource() throws {
    let doc = MarkdownDocument()
    try doc.read(from: Data("# a **b**".utf8), ofType: "Markdown")
    doc.makeWindowControllers()
    doc.textView?.togglePreview(nil)
    #expect(doc.textView?.string == "a b")
    #expect(try doc.data(ofType: "Markdown") == Data("# a **b**".utf8))
}

@MainActor @Test func externalChangeDuringPreviewUpdatesSource() throws {
    let doc = MarkdownDocument()
    doc.makeWindowControllers()
    doc.textView?.togglePreview(nil)
    try doc.read(from: Data("**new**".utf8), ofType: "Markdown")
    #expect(doc.textView?.string == "new")
    #expect(try doc.data(ofType: "Markdown") == Data("**new**".utf8))
}

@MainActor @Test func viewMenuHasPreviewAndFileMenuHasQuickOpen() {
    let menu = makeMainMenu()
    let preview = menu.item(withTitle: "View")?.submenu?.items.first { $0.action == #selector(EditorTextView.togglePreview(_:)) }
    #expect(preview?.keyEquivalent == "e")
    let quick = menu.item(withTitle: "File")?.submenu?.items.first { $0.action == #selector(AppDelegate.quickOpen(_:)) }
    #expect(quick?.keyEquivalent == "k")
}
