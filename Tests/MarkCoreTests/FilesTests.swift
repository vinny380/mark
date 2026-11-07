import Foundation
import Testing
@testable import MarkCore

@Test func listsOnlyMarkdownFilesNewestFirst() throws {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: d.appendingPathComponent("sub.md"), withIntermediateDirectories: true)
    for (name, age) in [("old.md", 300.0), ("new.markdown", 0), ("notes.txt", 0), ("MID.MD", 100), (".hidden.md", 0)] {
        let u = d.appendingPathComponent(name)
        try "x".write(to: u, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: u.path)
    }
    #expect(markdownFiles(in: d).map(\.lastPathComponent) == ["new.markdown", "MID.MD", "old.md"])
    #expect(markdownFiles(in: d.appendingPathComponent("missing")).isEmpty)
}

@Test func noisePathsAreSkipped() {
    #expect(isNoisePath("/Users/v/proj/node_modules/x/README.md"))
    #expect(isNoisePath("/Users/v/.cache/notes.md"))
    #expect(isNoisePath("/Users/v/Library/Caches/a.md"))
    #expect(isNoisePath("/Users/v/proj/.build/checkouts/a.md"))
    #expect(isNoisePath("/Applications/Xcode.app/Contents/README.md"))
    #expect(isNoisePath("/Users/v/Apps/Tool.app/Contents/notes.md"))
    #expect(isNoisePath("/System/Library/x.md"))
    #expect(isNoisePath("/opt/homebrew/Cellar/x/README.md"))
    #expect(isNoisePath("/usr/local/share/doc/x.md"))
    #expect(isNoisePath("/private/var/folders/x.md"))
    #expect(isNoisePath("/Users/v/proj/Frameworks/Foo.framework/README.md"))
    #expect(!isNoisePath("/Volumes/Backup/notes/plan.md"))
    #expect(!isNoisePath("/Users/v/Desktop/notes.md"))
    #expect(!isNoisePath("/Users/v/code/library-notes/a.md"))
}

@Test func displayPathAbbreviatesHome() {
    let home = URL(fileURLWithPath: "/Users/v")
    #expect(displayPath(URL(fileURLWithPath: "/Users/v/Desktop/a.md"), home: home) == "~/Desktop")
    #expect(displayPath(URL(fileURLWithPath: "/Users/v/a.md"), home: home) == "~")
    #expect(displayPath(URL(fileURLWithPath: "/Volumes/X/a.md"), home: home) == "/Volumes/X")
    #expect(displayPath(URL(fileURLWithPath: "/Users/vinny/a.md"), home: home) == "/Users/vinny")
}

@Test func resolvesImageSources() {
    let base = URL(fileURLWithPath: "/Users/v/notes", isDirectory: true)
    #expect(imageURL("https://x.com/a.png", base: base)?.absoluteString == "https://x.com/a.png")
    #expect(imageURL("img/a b.png", base: base)?.path == "/Users/v/notes/img/a b.png")
    #expect(imageURL("img/a%20b.png", base: base)?.path == "/Users/v/notes/img/a b.png")
    #expect(imageURL("/tmp/a.png", base: base)?.path == "/tmp/a.png")
    #expect(imageURL("file:///tmp/a.png", base: nil)?.path == "/tmp/a.png")
    #expect(imageURL("img/a.png", base: nil) == nil)
    #expect(imageURL("a.png", base: URL(fileURLWithPath: "/Users/v/notes"))?.path == "/Users/v/notes/a.png") // no trailing slash
    #expect(imageURL("../a.png", base: base)?.path == "/Users/v/a.png")
    #expect(imageURL("javascript:alert(1)", base: base) == nil)
}
