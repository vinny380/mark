import Foundation
import Testing
@testable import MarkCore

@Test func imageMarkdownEncodesSpacesAndParens() {
    #expect(imageMarkdown(alt: "cat", path: "assets/cat.png") == "![cat](assets/cat.png)")
    #expect(imageMarkdown(alt: "a]b", path: "assets/my pic (1).png") == "![ab](assets/my%20pic%20%281%29.png)")
    #expect(imageMarkdown(alt: "x", path: "https://x.com/a b.png") == "![x](https://x.com/a%20b.png)")
    // round-trips through the tokenizer and resolver
    let md = imageMarkdown(alt: "p", path: "assets/my pic (1).png")
    let src = MarkdownStyler.runs(in: md).compactMap { if case .image(let s) = $0.style { s } else { nil } }.first
    #expect(imageURL(src ?? "", base: URL(fileURLWithPath: "/n"))?.path == "/n/assets/my pic (1).png")
}

@Test func assetNamesAreTidyAndUnique() {
    let taken: Set<String> = ["photo.png", "photo-2.png"]
    #expect(assetName(for: "photo.png") { taken.contains($0) } == "photo-3.png")
    #expect(assetName(for: "Screen Shot 2026.png") { _ in false } == "Screen-Shot-2026.png")
    #expect(assetName(for: "noext") { _ in false } == "noext")
}

@Test func relativePathOnlyInsideFolder() {
    let dir = URL(fileURLWithPath: "/Users/v/notes")
    #expect(relativePath(of: URL(fileURLWithPath: "/Users/v/notes/img/a.png"), inside: dir) == "img/a.png")
    #expect(relativePath(of: URL(fileURLWithPath: "/Users/v/notesX/a.png"), inside: dir) == nil)
    #expect(relativePath(of: URL(fileURLWithPath: "/Users/v/a.png"), inside: dir) == nil)
}

/// "|" marks the caret, as in EditingTests.
private func insert(_ marked: String, _ block: String) -> String {
    let ns = marked as NSString
    let at = ns.range(of: "|").location
    let text = ns.replacingCharacters(in: NSRange(location: at, length: 1), with: "")
    let e = insertBlock(text, at: at, block)
    let out = (text as NSString).replacingCharacters(in: e.range, with: e.replacement) as NSString
    return out.replacingCharacters(in: NSRange(location: e.selection.location, length: 0), with: "|")
}

@Test func blocksGoOnTheirOwnLine() {
    #expect(insert("|", "IMG") == "IMG\n|")
    #expect(insert("hello|", "IMG") == "hello\nIMG\n|")
    #expect(insert("he|llo", "IMG") == "he\nIMG\n|llo")
    #expect(insert("a\n|b", "IMG") == "a\nIMG\n|b")
    #expect(insert("a\n|", "IMG") == "a\nIMG\n|")
}
