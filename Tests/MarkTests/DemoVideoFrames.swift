import AppKit
import Testing
@testable import Mark
import MarkCore

/// Renders the UI states for the launch video with Mark's real editor (typing, image drop, ⌘E, ⌘P).
/// Opt-in: MARK_DEMO_OUT=<dir> MARK_DEMO_PHOTO=<jpg> swift test --filter renderDemoFrames
/// Writes <dir>/ui/*.png (2x) and <dir>/ui/frames.json (caret position per frame, top-left origin, points).
/// MARK_DEMO_NOTES=<dir> picks where the fake notes live (shown in ⌘P's path); it must not exist yet,
/// or must be a folder this renderer made (it carries a .mark-demo marker).
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["MARK_DEMO_OUT"] != nil))
func renderDemoFrames() throws {
    let env = ProcessInfo.processInfo.environment
    let out = URL(fileURLWithPath: env["MARK_DEMO_OUT"]!).appendingPathComponent("ui")
    let notes = URL(fileURLWithPath: env["MARK_DEMO_NOTES"] ?? env["MARK_DEMO_OUT"]! + "/demo-notes")
    let marker = notes.appendingPathComponent(".mark-demo")
    if FileManager.default.fileExists(atPath: notes.path) {
        try #require(FileManager.default.fileExists(atPath: marker.path), "\(notes.path) exists and isn't a demo folder; refusing to touch it")
        try FileManager.default.removeItem(at: notes)
    }
    try? FileManager.default.removeItem(at: out)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: notes.appendingPathComponent("Archive"), withIntermediateDirectories: true)
    try "".write(to: marker, atomically: true, encoding: .utf8)
    for (name, age) in [("Weekly notes.md", 3600.0), ("Ideas.md", 7200), ("Reading list.md", 86400), ("Interview prep.md", 172800)] {
        let u = notes.appendingPathComponent(name)
        try "# \(name)".write(to: u, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: u.path)
    }
    let note = notes.appendingPathComponent("Launch plan.md")
    try "".write(to: note, atomically: true, encoding: .utf8)

    let doc = MarkdownDocument()
    try doc.read(from: Data(), ofType: "Markdown")
    doc.fileURL = note
    doc.makeWindowControllers()
    let window = doc.windowControllers[0].window!
    window.appearance = NSAppearance(named: .darkAqua)
    window.setContentSize(NSSize(width: 1180, height: 720))
    let tv = doc.textView!
    let content = window.contentView!

    var meta: [[String: Any]] = []
    func snap(_ name: String) throws {
        content.layoutSubtreeIfNeeded()
        let size = content.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        content.cacheDisplay(in: content.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
        // caret in content-view points, top-left origin
        let screen = tv.firstRect(forCharacterRange: tv.selectedRange(), actualRange: nil)
        let inWindow = window.convertFromScreen(screen)
        let r = content.convert(inWindow, from: nil)
        let top = content.isFlipped ? r.minY : size.height - r.maxY
        meta.append(["name": name, "caret": [r.minX, top, max(r.width, 2), r.height]])
    }

    var n = 0
    func type(_ s: String) throws {
        for ch in s {
            tv.insertText(String(ch), replacementRange: tv.selectedRange())
            tv.scrollRangeToVisible(tv.selectedRange())
            try snap(String(format: "type-%03d", n)); n += 1
        }
    }
    func key(_ action: () -> Void) throws {
        action()
        tv.scrollRangeToVisible(tv.selectedRange())
        try snap(String(format: "type-%03d", n)); n += 1
    }

    try snap("empty")
    try type("# Launch plan")
    try key { tv.insertNewline(nil) }; try key { tv.insertNewline(nil) }
    try type("Ship **Mark** on Friday. Native, tiny, *fast*.")
    try key { tv.insertNewline(nil) }; try key { tv.insertNewline(nil) }
    try type("- [ ] Record the demo")
    try key { tv.insertNewline(nil) }          // Return continues the to-do list
    try type("Make the icon")
    try key { tv.toggleTodoItem(nil) }         // ⌘↩ checks it off
    try snap("typed")

    // Drag a photo in from "Downloads": copied into ./assets, shown inline.
    tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
    tv.insertNewline(nil); tv.insertNewline(nil)
    let pb = NSPasteboard(name: .init("mark-demo-\(UUID().uuidString)"))
    pb.clearContents()
    pb.writeObjects([URL(fileURLWithPath: env["MARK_DEMO_PHOTO"]!) as NSURL])
    #expect(tv.insertImages(from: pb, at: tv.selectedRange().location))
    tv.scrollRangeToVisible(tv.selectedRange())
    try snap("dropped")

    tv.togglePreview(nil)
    tv.scroll(.zero)
    try snap("preview")
    tv.togglePreview(nil)

    for (i, q) in ["", "w", "wk", "wkn"].enumerated() {
        let rep = QuickOpen.shared.snapshot(folder: notes, query: q, appearance: NSAppearance(named: .darkAqua))!
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("palette-\(i).png"))
    }
    let sampleOutline = outline("# Launch plan\n## Goals\n## Timeline\n### Week 1\n### Week 2\n## Risks")
    let sampleCommands: [QuickOpen.Command] = [("Toggle Preview", "⌘E"), ("New Markdown File", "⌘N"), ("Reveal in Finder", ""),
                                               ("Copy File Path", ""), ("Bigger Text", "⌘+"), ("Smaller Text", "⌘−")].map { .init(title: $0.0, shortcut: $0.1) {} }
    for (name, q) in [("palette-headings", "#"), ("palette-commands", ">")] {
        let rep = QuickOpen.shared.snapshot(folder: notes, query: q, appearance: NSAppearance(named: .darkAqua),
                                            headings: sampleOutline, commands: sampleCommands)!
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
    }
    let json = try JSONSerialization.data(withJSONObject: ["contentSize": [content.bounds.width, content.bounds.height], "frames": meta], options: .prettyPrinted)
    try json.write(to: out.appendingPathComponent("frames.json"))
    print("demo frames:", n, "→", out.path)
}

/// Opt-in, needs internet: MARK_DEMO_OUT=<dir> swift test --filter renderDiagramPreview → <dir>/ui/diagrams.png
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["MARK_DEMO_OUT"] != nil))
func renderDiagramPreview() async throws {
    let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MARK_DEMO_OUT"]!).appendingPathComponent("ui")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let doc = MarkdownDocument()
    try doc.read(from: Data("""
    # Release flow

    ```mermaid
    graph LR
      A[Write] --> B{Ship?}
      B -->|yes| C[Tweet]
      B -->|no| A
    ```

    Euler, inline: $e^{i\\pi} + 1 = 0$ and a block:

    $$
    \\int_0^1 x^2\\,dx = \\frac{1}{3}
    $$
    """.utf8), ofType: "Markdown")
    doc.makeWindowControllers()
    let window = doc.windowControllers[0].window!
    window.appearance = NSAppearance(named: .darkAqua)
    window.setContentSize(NSSize(width: 1180, height: 720))
    doc.textView!.togglePreview(nil)
    let deadline = Date().addingTimeInterval(25) // first run downloads the libraries
    while Date() < deadline && (doc.textView!.textStorage!.string.contains("graph LR") || doc.textView!.textStorage!.string.contains("frac")) {
        try await Task.sleep(for: .milliseconds(200)) // yield: the renderer finishes on the main actor
    }
    let content = window.contentView!
    let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
    content.cacheDisplay(in: content.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("diagrams.png"))
    #expect(!doc.textView!.textStorage!.string.contains("graph LR")) // rendered, not showing source
}

/// Second launch cut (opt-in, needs internet for Mermaid/MathJax):
/// MARK_DEMO_OUT=<dir> MARK_DEMO_NOTES=~/Notes swift test --filter renderDemoV2 → <dir>/ui2/
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["MARK_DEMO_OUT"] != nil))
func renderDemoV2() async throws {
    let env = ProcessInfo.processInfo.environment
    let out = URL(fileURLWithPath: env["MARK_DEMO_OUT"]!).appendingPathComponent("ui2")
    let notes = URL(fileURLWithPath: env["MARK_DEMO_NOTES"] ?? env["MARK_DEMO_OUT"]! + "/demo-notes")
    let marker = notes.appendingPathComponent(".mark-demo")
    if FileManager.default.fileExists(atPath: notes.path) {
        try #require(FileManager.default.fileExists(atPath: marker.path), "\(notes.path) exists and isn't a demo folder; refusing to touch it")
        try FileManager.default.removeItem(at: notes)
    }
    try? FileManager.default.removeItem(at: out)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
    try "".write(to: marker, atomically: true, encoding: .utf8)
    let note = notes.appendingPathComponent("Untitled.md")
    try "".write(to: note, atomically: true, encoding: .utf8)

    let doc = MarkdownDocument()
    try doc.read(from: Data(), ofType: "Markdown")
    doc.fileURL = note
    doc.makeWindowControllers()
    let window = doc.windowControllers[0].window!
    window.appearance = NSAppearance(named: .darkAqua)
    window.setContentSize(NSSize(width: 1180, height: 720))
    let tv = doc.textView!, content = window.contentView!

    var meta: [[String: Any]] = []
    func snap(_ name: String) throws {
        content.layoutSubtreeIfNeeded()
        let size = content.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        content.cacheDisplay(in: content.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
        let r = content.convert(window.convertFromScreen(tv.firstRect(forCharacterRange: tv.selectedRange(), actualRange: nil)), from: nil)
        meta.append(["name": name, "caret": [r.minX, content.isFlipped ? r.minY : size.height - r.maxY, max(r.width, 2), r.height]])
    }
    var n = 0
    func step(_ action: () -> Void) throws {
        action()
        tv.scrollRangeToVisible(tv.selectedRange())
        try snap(String(format: "type-%03d", n)); n += 1
    }
    func type(_ s: String) throws { for ch in s { try step { tv.insertText(String(ch), replacementRange: tv.selectedRange()) } } }

    try snap("empty")
    try type("# Launch plan")
    try step { tv.insertNewline(nil) }; try step { tv.insertNewline(nil) }
    try type("Ship **Mark** on Friday.")
    try step { tv.insertNewline(nil) }; try step { tv.insertNewline(nil) }
    try type("- [ ] Record the demo")
    try step { tv.insertNewline(nil) }
    try type("Make the icon")
    try step { tv.toggleTodoItem(nil) }
    tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
    tv.insertNewline(nil); tv.insertNewline(nil); tv.insertNewline(nil) // end the list, then a blank line

    // ⌘V: a diagram, a timeline and some math, pasted in one go
    tv.insertText("""
    ```mermaid
    graph LR
      A[Write] --> B[Preview] --> C[Ship]
    ```

    ## Timeline

    - **Fri**: ship it
    - **Mon**: post the demo

    ## Math

    Euler, for fun: $e^{i\\pi} + 1 = 0$

    $$
    \\int_0^1 x^2\\,dx = \\frac{1}{3}
    $$
    """, replacementRange: tv.selectedRange())
    tv.scrollRangeToVisible(tv.selectedRange())
    try snap("pasted")

    tv.togglePreview(nil)
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline && (tv.string.contains("graph LR") || tv.string.contains("frac")) {
        try await Task.sleep(for: .milliseconds(200))
    }
    #expect(!tv.string.contains("graph LR"))
    tv.scroll(.zero)
    try snap("preview-top")

    let headings = outline(tv.markdown)
    for (i, q) in ["#", "#m", "#ma"].enumerated() {
        let rep = QuickOpen.shared.snapshot(folder: notes, query: q, appearance: NSAppearance(named: .darkAqua), headings: headings)!
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("palette-\(i).png"))
    }
    tv.jump(to: headings.first { $0.title == "Math" }!)
    try snap("preview-math")

    // `mark standup` from Terminal: a fresh, empty note
    tv.togglePreview(nil)
    tv.setMarkdown("")
    try snap("blank")

    let json = try JSONSerialization.data(withJSONObject: ["contentSize": [content.bounds.width, content.bounds.height], "frames": meta], options: .prettyPrinted)
    try json.write(to: out.appendingPathComponent("frames.json"))
    print("demo v2 frames:", n, "→", out.path)
}

/// Launch cut (opt-in, needs internet for Mermaid/MathJax):
/// MARK_DEMO_OUT=<dir> MARK_DEMO_NOTES=~/Notes MARK_DEMO_PHOTO=<jpg> swift test --filter renderDemoV3 → <dir>/ui3/
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["MARK_DEMO_OUT"] != nil))
func renderDemoV3() async throws {
    let env = ProcessInfo.processInfo.environment
    let light = env["MARK_DEMO_APPEARANCE"] == "light"           // MARK_DEMO_APPEARANCE=light → <dir>/ui3-light
    let appearance = NSAppearance(named: light ? .aqua : .darkAqua)
    let out = URL(fileURLWithPath: env["MARK_DEMO_OUT"]!).appendingPathComponent(light ? "ui3-light" : "ui3")
    let notes = URL(fileURLWithPath: env["MARK_DEMO_NOTES"] ?? env["MARK_DEMO_OUT"]! + "/demo-notes")
    let marker = notes.appendingPathComponent(".mark-demo")
    if FileManager.default.fileExists(atPath: notes.path) {
        try #require(FileManager.default.fileExists(atPath: marker.path), "\(notes.path) exists and isn't a demo folder; refusing to touch it")
        try FileManager.default.removeItem(at: notes)
    }
    try? FileManager.default.removeItem(at: out)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
    try "".write(to: marker, atomically: true, encoding: .utf8)
    let note = notes.appendingPathComponent("Untitled.md")
    try "".write(to: note, atomically: true, encoding: .utf8)

    let doc = MarkdownDocument()
    try doc.read(from: Data(), ofType: "Markdown")
    doc.fileURL = note
    doc.makeWindowControllers()
    let window = doc.windowControllers[0].window!
    window.appearance = appearance
    window.setContentSize(NSSize(width: 1180, height: 720))
    let tv = doc.textView!, content = window.contentView!

    var meta: [[String: Any]] = []
    func snap(_ name: String) throws {
        content.layoutSubtreeIfNeeded()
        let size = content.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        content.cacheDisplay(in: content.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
        let r = content.convert(window.convertFromScreen(tv.firstRect(forCharacterRange: tv.selectedRange(), actualRange: nil)), from: nil)
        meta.append(["name": name, "caret": [r.minX, content.isFlipped ? r.minY : size.height - r.maxY, max(r.width, 2), r.height]])
    }
    var n = 0
    func step(_ action: () -> Void) throws {
        action()
        tv.scrollRangeToVisible(tv.selectedRange())
        try snap(String(format: "type-%03d", n)); n += 1
    }
    func type(_ s: String) throws { for ch in s { try step { tv.insertText(String(ch), replacementRange: tv.selectedRange()) } } }
    func select(_ word: String) { tv.setSelectedRange((tv.string as NSString).range(of: word)) }

    try snap("empty")
    try type("# Launch plan")
    try step { tv.insertNewline(nil) }; try step { tv.insertNewline(nil) }
    try type("Ship Mark on Friday.")
    try step { tv.insertNewline(nil) }; try step { tv.insertNewline(nil) }
    try type("- [ ] Record the demo")
    try step { tv.insertNewline(nil) }
    try type("Make the icon")
    try step { tv.toggleTodoItem(nil) }                            // ⌘↩

    select("Mark"); try snap("bold-sel")
    tv.toggleBold(nil); try snap("bold")                           // ⌘B
    select("Friday"); try snap("link-sel")
    let e = linkPaste(tv.string, tv.selectedRange(), "https://cal.com/launch")!   // ⌘V a URL onto a word
    tv.insertText(e.replacement, replacementRange: e.range); tv.setSelectedRange(e.selection)
    try snap("link")
    tv.setSelectedRange(NSRange(location: (tv.string as NSString).range(of: "Make the icon").location, length: 0))
    try snap("move-sel")
    tv.moveLineUp(nil); try snap("move")                           // ⌥↑

    tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
    tv.insertNewline(nil); tv.insertNewline(nil); tv.insertNewline(nil)
    tv.insertText("""
    ```mermaid
    graph LR
      A[Write] --> B[Preview] --> C[Ship]
    ```

    ## Math

    Euler, for fun: $e^{i\\pi} + 1 = 0$

    $$
    \\int_0^1 x^2\\,dx = \\frac{1}{3}
    $$

    ## Photo

    """, replacementRange: tv.selectedRange())
    tv.scrollRangeToVisible(tv.selectedRange())
    try snap("pasted")                                             // ⌘V

    let pb = NSPasteboard(name: .init("mark-demo-\(UUID().uuidString)"))
    pb.clearContents()
    pb.writeObjects([URL(fileURLWithPath: env["MARK_DEMO_PHOTO"]!) as NSURL])
    #expect(tv.insertImages(from: pb, at: tv.selectedRange().location))
    tv.scrollRangeToVisible(tv.selectedRange())
    try snap("dropped")                                            // drag & drop

    tv.togglePreview(nil)                                          // ⌘E
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline && (tv.string.contains("graph LR") || tv.string.contains("frac")) {
        try await Task.sleep(for: .milliseconds(200))
    }
    #expect(!tv.string.contains("graph LR"))
    tv.scroll(.zero)
    try snap("preview-top")
    let headings = outline(tv.markdown)
    for (i, q) in ["#", "#p", "#ph"].enumerated() {
        let rep = QuickOpen.shared.snapshot(folder: notes, query: q, appearance: appearance, headings: headings)!
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("palette-\(i).png"))
    }
    tv.jump(to: headings.first { $0.title == "Photo" }!)            // ⌘P # → ↩
    try snap("preview-photo")

    tv.togglePreview(nil)
    tv.setMarkdown("")
    try snap("blank")
    let json = try JSONSerialization.data(withJSONObject: ["contentSize": [content.bounds.width, content.bounds.height], "frames": meta], options: .prettyPrinted)
    try json.write(to: out.appendingPathComponent("frames.json"))
    print("demo v3 frames:", n, "→", out.path)
}
