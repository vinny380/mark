import Foundation
import Testing
@testable import MarkCore

@Test func fuzzyMatchesSubsequenceCaseInsensitive() {
    #expect(fuzzyMatch("wkn", "Weekly notes.md")?.positions == [0, 3, 7])
    #expect(fuzzyMatch("WEEK", "weekly.md") != nil)
    #expect(fuzzyMatch("xyz", "Weekly notes.md") == nil)
    #expect(fuzzyMatch("", "anything")?.positions == [])
}

@Test func fuzzyRanksTightEarlyMatchesFirst() {
    let a = fuzzyMatch("plan", "plan.md")!.score
    let b = fuzzyMatch("plan", "implementation_plan.md")!.score
    let c = fuzzyMatch("plan", "p_l_a_n.md")!.score
    #expect(a > b)
    #expect(b > c)
}

@Test func fuzzyPrefersWordStartAlignment() {
    // "plan" at the word start beats the scattered letters earlier in the name
    #expect(fuzzyMatch("plan", "implementation_plan.md")?.positions == [15, 16, 17, 18])
}

@Test func listsBrowsableSubfoldersAlphabetically() throws {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    for name in ["b", "A", ".git", "node_modules", "Tool.app", "c10", "c9"] {
        try FileManager.default.createDirectory(at: d.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    try "x".write(to: d.appendingPathComponent("file.md"), atomically: true, encoding: .utf8)
    #expect(browsableFolders(in: d).map(\.lastPathComponent) == ["A", "b", "c9", "c10"])
}

@Test func parentStopsAtRoot() {
    #expect(parentFolder(of: URL(fileURLWithPath: "/Users/v")).path == "/Users")
    #expect(parentFolder(of: URL(fileURLWithPath: "/")).path == "/")
}
