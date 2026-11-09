import Foundation
import Testing
@testable import MarkCore

private func tempDir(_ name: String = "dir") throws -> URL {
    let d = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent(name)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

@Test func createsUntitled() throws {
    let d = try tempDir()
    let url = try createUntitledMarkdown(in: d)
    #expect(url.lastPathComponent == "Untitled.md")
    #expect(url.deletingLastPathComponent().standardizedFileURL == d.standardizedFileURL)
    #expect(try Data(contentsOf: url).isEmpty)
}

@Test func incrementsWhenTaken() throws {
    let d = try tempDir()
    try "keep".write(to: d.appendingPathComponent("Untitled.md"), atomically: true, encoding: .utf8)
    #expect(try createUntitledMarkdown(in: d).lastPathComponent == "Untitled 2.md")
    #expect(try String(contentsOf: d.appendingPathComponent("Untitled.md"), encoding: .utf8) == "keep")
    #expect(try createUntitledMarkdown(in: d).lastPathComponent == "Untitled 3.md")
}

@Test func throwsForMissingDirectory() throws {
    let d = try tempDir()
    #expect(throws: (any Error).self) { try createUntitledMarkdown(in: d.appendingPathComponent("nope")) }
}

@Test func roundTripsPathWithSpaces() throws {
    let d = try tempDir("My Notes ünï")
    #expect(directory(fromNewFileRequest: newFileRequestURL(directory: d))?.path == d.path)
}

@Test func rejectsBadRequests() throws {
    let d = try tempDir()
    let file = d.appendingPathComponent("f.txt")
    try "x".write(to: file, atomically: true, encoding: .utf8)
    let bad = [
        "https://new?dir=/tmp",
        "mark://other?dir=/tmp",
        "mark://new",
        "mark://new?dir=/does/not/exist",
        newFileRequestURL(directory: file).absoluteString,
    ]
    for s in bad { #expect(directory(fromNewFileRequest: URL(string: s)!) == nil, "\(s)") }
}

/// The Finder extension carries its own copy of newFileRequestURL; it must stay byte-for-byte the same function.
@Test func finderExtensionBuildsTheSameRequest() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func body(_ file: String) throws -> String {
        let s = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
        let start = try #require(s.range(of: "func newFileRequestURL(directory: URL) -> URL {"))
        let end = try #require(s.range(of: "return c.url!", range: start.upperBound..<s.endIndex))
        return String(s[start.lowerBound..<end.upperBound])
    }
    #expect(try body("Sources/MarkFinder/FinderSync.swift") == body("Sources/MarkCore/NewFile.swift").replacingOccurrences(of: "public func", with: "func"))
}
