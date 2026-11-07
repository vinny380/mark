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
