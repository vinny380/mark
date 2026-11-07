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
    #expect(quick?.keyEquivalent == "p")
}

@MainActor private func shortcut(_ menu: NSMenu, _ action: Selector, tag: Int? = nil) -> String? {
    for top in menu.items {
        for i in top.submenu?.items ?? [] where i.action == action && (tag == nil || i.tag == tag) {
            let m = i.keyEquivalentModifierMask
            return (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "") + (m.contains(.shift) ? "⇧" : "")
                + (m.contains(.command) ? "⌘" : "") + i.keyEquivalent
        }
    }
    return nil
}

@MainActor @Test func formatMenuShortcuts() {
    let menu = makeMainMenu()
    #expect(shortcut(menu, #selector(EditorTextView.toggleBold(_:))) == "⌘b")
    #expect(shortcut(menu, #selector(EditorTextView.toggleItalic(_:))) == "⌘i")
    #expect(shortcut(menu, #selector(EditorTextView.toggleStrikethrough(_:))) == "⇧⌘x")
    #expect(shortcut(menu, #selector(EditorTextView.toggleInlineCode(_:))) == "⇧⌘e")
    #expect(shortcut(menu, #selector(EditorTextView.insertLink(_:))) == "⌘k")
    #expect(shortcut(menu, #selector(EditorTextView.setHeadingLevel(_:)), tag: 1) == "⌥⌘1")
    #expect(shortcut(menu, #selector(EditorTextView.setHeadingLevel(_:)), tag: 3) == "⌥⌘3")
    #expect(shortcut(menu, #selector(EditorTextView.setHeadingLevel(_:)), tag: 0) == "⌥⌘0")
    #expect(shortcut(menu, #selector(EditorTextView.toggleTodoItem(_:))) == "⌘\r")
}

@MainActor private func editor(_ text: String, _ sel: NSRange) -> (EditorTextView, NSWindow) {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
    let tv = EditorTextView(frame: w.contentView!.bounds)
    w.contentView = tv
    tv.setMarkdown(text)
    tv.setSelectedRange(sel)
    return (tv, w)
}

@MainActor @Test func boldWrapsSelectionAndUndoRestores() {
    let (tv, w) = editor("a b", NSRange(location: 2, length: 1))
    w.undoManager?.groupsByEvent = false // no event loop in tests: group by hand
    w.undoManager?.beginUndoGrouping()
    tv.toggleBold(nil)
    w.undoManager?.endUndoGrouping()
    #expect(tv.string == "a **b**")
    #expect(tv.selectedRange() == NSRange(location: 4, length: 1))
    w.undoManager?.undo()
    #expect(tv.string == "a b")
}

@MainActor @Test func returnContinuesListAndTabIndents() {
    let (tv, _) = editor("- a", NSRange(location: 3, length: 0))
    tv.insertNewline(nil)
    #expect(tv.string == "- a\n- ")
    tv.insertTab(nil)
    #expect(tv.string == "- a\n  - ")
    tv.insertBacktab(nil)
    #expect(tv.string == "- a\n- ")
}

@MainActor @Test func headingTodoAndLinkCommands() {
    let (tv, _) = editor("title", NSRange(location: 5, length: 0))
    let h2 = NSMenuItem(); h2.tag = 2
    tv.setHeadingLevel(h2)
    #expect(tv.string == "## title")
    tv.toggleTodoItem(nil)
    #expect(tv.string == "- [ ] ## title")
    tv.setMarkdown("see docs")
    tv.setSelectedRange(NSRange(location: 4, length: 4))
    tv.insertLink(nil)
    #expect(tv.string == "see [docs]()")
    #expect(tv.selectedRange() == NSRange(location: 11, length: 0))
}

@MainActor @Test func formattingIsDisabledInPreview() {
    let (tv, _) = editor("a b", NSRange(location: 2, length: 1))
    tv.togglePreview(nil)
    let bold = NSMenuItem(title: "Bold", action: #selector(EditorTextView.toggleBold(_:)), keyEquivalent: "b")
    #expect(!tv.validateMenuItem(bold))
    tv.toggleBold(nil)
    #expect(tv.markdown == "a b")
}

private func png(_ w: CGFloat, _ h: CGFloat, in dir: URL, _ name: String) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
}

private func attachments(_ s: NSAttributedString) -> [NSTextAttachment] {
    var out: [NSTextAttachment] = []
    s.enumerateAttribute(.attachment, in: NSRange(location: 0, length: s.length)) { v, _, _ in
        if let a = v as? NSTextAttachment { out.append(a) }
    }
    return out
}

@MainActor @Test func previewShowsLocalImagesAndAltTextForUnloadedOnes() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try png(40, 20, in: dir, "pic.png")
    let s = Theme.preview("a ![pic](pic.png) b ![web shot](https://example.invalid/x.png)", base: dir, maxWidth: 600)
    let a = attachments(s)
    #expect(a.count == 1)
    #expect(a.first?.bounds.size == CGSize(width: 40, height: 20))
    #expect(s.string.hasSuffix("b web shot")) // remote image still loading → alt text
}

@MainActor @Test func wideImagesScaleDownToTheColumn() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try png(2000, 1000, in: dir, "wide.png")
    let a = attachments(Theme.preview("![](wide.png)", base: dir, maxWidth: 600))
    #expect(a.first?.bounds.size == CGSize(width: 600, height: 300))
}

// MARK: Drag/paste images

@MainActor private func noteInTempFolder(_ text: String = "hello") throws -> (MarkdownDocument, EditorTextView, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let note = dir.appendingPathComponent("note.md")
    try text.write(to: note, atomically: true, encoding: .utf8)
    let doc = MarkdownDocument()
    try doc.read(from: Data(text.utf8), ofType: "Markdown")
    doc.fileURL = note
    doc.makeWindowControllers()
    return (doc, doc.textView!, dir)
}

@MainActor private func pasteboard(_ write: (NSPasteboard) -> Void) -> NSPasteboard {
    let pb = NSPasteboard(name: .init("mark-test-\(UUID().uuidString)"))
    pb.clearContents()
    write(pb)
    return pb
}

@MainActor @Test func droppedImageFileIsCopiedIntoAssets() throws {
    let (_, tv, dir) = try noteInTempFolder()
    let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
    try png(40, 20, in: elsewhere, "My Pic.png")
    let pb = pasteboard { $0.writeObjects([elsewhere.appendingPathComponent("My Pic.png") as NSURL]) }
    #expect(tv.insertImages(from: pb, at: 5))
    #expect(tv.string == "hello\n![My Pic](assets/My-Pic.png)\n")
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("assets/My-Pic.png").path))
}

@MainActor @Test func imageAlreadyNextToTheNoteIsLinkedNotCopied() throws {
    let (_, tv, dir) = try noteInTempFolder("")
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("img"), withIntermediateDirectories: true)
    try png(10, 10, in: dir.appendingPathComponent("img"), "a.png")
    let pb = pasteboard { $0.writeObjects([dir.appendingPathComponent("img/a.png") as NSURL]) }
    #expect(tv.insertImages(from: pb, at: 0))
    #expect(tv.string == "![a](img/a.png)\n")
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("assets").path))
}

@MainActor @Test func pastedScreenshotIsSavedAsPNG() throws {
    let (_, tv, dir) = try noteInTempFolder("")
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let pb = pasteboard { $0.setData(rep.representation(using: .png, properties: [:]), forType: .png) }
    #expect(tv.insertImages(from: pb, at: 0))
    let files = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("assets").path)
    #expect(files.count == 1)
    #expect(files.first?.hasSuffix(".png") == true)
    #expect(tv.string == "![Pasted image](assets/\(files.first ?? ""))\n")
}

@MainActor @Test func webImageIsLinkedByURL() throws {
    let (_, tv, dir) = try noteInTempFolder("")
    let pb = pasteboard { $0.writeObjects([URL(string: "https://x.com/photos/cat.jpg")! as NSURL]) }
    #expect(tv.insertImages(from: pb, at: 0))
    #expect(tv.string == "![cat](https://x.com/photos/cat.jpg)\n")
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("assets").path))
}

@MainActor @Test func plainTextAndPageLinksAreNotImages() throws {
    let (_, tv, _) = try noteInTempFolder("")
    #expect(!tv.insertImages(from: pasteboard { $0.setString("just text", forType: .string) }, at: 0))
    #expect(!tv.insertImages(from: pasteboard { $0.writeObjects([URL(string: "https://x.com/article")! as NSURL]) }, at: 0))
}

@MainActor @Test func imagesShowInlineWhileEditing() throws {
    let (_, tv, dir) = try noteInTempFolder("")
    try png(2000, 1000, in: dir, "wide.png")
    tv.setMarkdown("intro\n![w](wide.png)\nafter")
    let overlays = tv.subviews.filter { $0 is ImageOverlay }
    #expect(overlays.count == 1)
    let frame = overlays.first?.frame ?? .zero
    #expect(frame.width > 100 && frame.width <= 720)
    #expect(abs(frame.width - 2 * frame.height) < 2) // keeps the 2:1 aspect ratio
    tv.togglePreview(nil)
    #expect(tv.subviews.filter { $0 is ImageOverlay }.isEmpty) // preview draws its own
}

@MainActor @Test func quickOpenRendersOffscreenAtRetina() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try "x".write(to: dir.appendingPathComponent("Weekly notes.md"), atomically: true, encoding: .utf8)
    let rep = QuickOpen.shared.snapshot(folder: dir, query: "wkn", appearance: NSAppearance(named: .darkAqua))
    #expect(rep?.pixelsWide == 1280)
    #expect(rep?.pixelsHigh == 880)
    #expect(QuickOpen.shared.isOnScreen == false)
}

@MainActor @Test func imageOnTheLastLineSitsRightUnderIt() throws {
    let (_, tv, dir) = try noteInTempFolder("")
    try png(400, 200, in: dir, "pic.png")
    tv.setMarkdown("![p](pic.png)\n") // image line is the last paragraph, then the empty last line
    let overlay = try #require(tv.subviews.first { $0 is ImageOverlay })
    // first line starts at the top inset (56) and is ~22pt tall; the picture belongs right below it, not after its reserved space
    #expect(overlay.frame.minY < tv.textContainerOrigin.y + 60)
}

@MainActor @Test func previewShowsRenderedDiagramsAndFallsBackToSource() {
    let md = "a\n```mermaid\ngraph LR\n```\nb $x^2$ c"
    let pic = NSImage(size: NSSize(width: 1200, height: 300))
    let s = Theme.preview(md, maxWidth: 600, dark: true) { kind, _ in kind == .mermaid ? pic : nil }
    let a = attachments(s)
    #expect(a.count == 1)
    #expect(a.first?.bounds.size == CGSize(width: 600, height: 150)) // scaled to the column
    #expect(s.string.hasSuffix("b x^2 c"))                           // inline math not rendered (offline) → its TeX
}

@MainActor @Test func copiedFromWriterShortcuts() {
    let menu = makeMainMenu()
    let up = String(UnicodeScalar(NSUpArrowFunctionKey)!), down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
    #expect(shortcut(menu, #selector(EditorTextView.moveLineUp(_:))) == "⌥" + up)
    #expect(shortcut(menu, #selector(EditorTextView.moveLineDown(_:))) == "⌥" + down)
    #expect(shortcut(menu, #selector(NSTextView.performTextFinderAction(_:)), tag: NSTextFinder.Action.showReplaceInterface.rawValue) == "⌥⌘f")
    #expect(shortcut(menu, #selector(NSTextView.performTextFinderAction(_:)), tag: NSTextFinder.Action.nextMatch.rawValue) == "⌘g")
    #expect(shortcut(menu, #selector(AppDelegate.makeTextBigger(_:))) == "⌘+")
    #expect(shortcut(menu, #selector(AppDelegate.makeTextSmaller(_:))) == "⌘-")
    #expect(shortcut(menu, #selector(AppDelegate.makeTextActualSize(_:))) == "⌘0")
    #expect(menu.item(withTitle: "File")?.submenu?.item(withTitle: "Open Recent")?.submenu != nil)
}

@MainActor @Test func moveLineCommand() {
    let (tv, _) = editor("a\nb\nc", NSRange(location: 2, length: 0))
    tv.moveLineUp(nil)
    #expect(tv.string == "b\na\nc")
    tv.moveLineDown(nil); tv.moveLineDown(nil)
    #expect(tv.string == "a\nc\nb")
}

@MainActor @Test func textSizeScalesEverything() {
    defer { Theme.scale = 1 }
    Theme.scale = 1.2
    #expect((Theme.baseAttributes[.font] as? NSFont)?.pointSize == 18)
    let delegate = AppDelegate()
    delegate.makeTextActualSize(nil)
    #expect(Theme.scale == 1)
    delegate.makeTextBigger(nil)
    #expect(abs(Theme.scale - 1.1) < 0.001)
    for _ in 0..<30 { delegate.makeTextSmaller(nil) }
    #expect(Theme.scale >= 0.7) // floor
}
