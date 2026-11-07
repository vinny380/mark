import AppKit
import Testing
@testable import Mark

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
