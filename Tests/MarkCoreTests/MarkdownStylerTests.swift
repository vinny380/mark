import Foundation
import Testing
@testable import MarkCore

private func run(_ loc: Int, _ len: Int, _ s: MarkdownStyle) -> StyleRun {
    StyleRun(range: NSRange(location: loc, length: len), style: s)
}
private func has(_ text: String, _ r: StyleRun) -> Bool { MarkdownStyler.runs(in: text).contains(r) }
private func styles(_ text: String) -> [MarkdownStyle] { MarkdownStyler.runs(in: text).map(\.style) }

@Test func headings() {
    #expect(has("# Hi", run(0, 4, .heading(1))))
    #expect(has("# Hi", run(0, 2, .syntax)))
    #expect(has("### H", run(0, 5, .heading(3))))
    #expect(!styles("#nospace").contains(.heading(1)))
}

@Test func bold() {
    #expect(has("a **b** c", run(2, 5, .bold)))
    #expect(has("a **b** c", run(2, 2, .syntax)))
    #expect(has("a **b** c", run(5, 2, .syntax)))
}

@Test func italic() {
    #expect(has("x *i* y", run(2, 3, .italic)))
    #expect(has("x *i* y", run(2, 1, .syntax)))
    #expect(has("x *i* y", run(4, 1, .syntax)))
}

@Test func listMarkersAreSyntaxNotItalic() {
    #expect(has("* item", run(0, 1, .listMarker)))
    #expect(!styles("* item").contains(.italic))
    #expect(has("1. one", run(0, 2, .listMarker)))
}

@Test func inlineCode() {
    #expect(has("`c`", run(0, 3, .code)))
    #expect(has("`c`", run(0, 1, .syntax)))
    #expect(has("`c`", run(2, 1, .syntax)))
}

@Test func link() {
    #expect(has("[a](http://x)", run(1, 1, .link("http://x"))))
    #expect(has("[a](http://x)", run(0, 1, .syntax)))
    #expect(has("[a](http://x)", run(2, 11, .syntax)))
}

@Test func quote() {
    #expect(has("> q", run(0, 3, .quote)))
    #expect(has("> q", run(0, 2, .syntax)))
}

@Test func fencedBlockSuppressesInlineStyles() {
    let t = "```\n# x **y**\n```"
    #expect(has(t, run(0, 17, .codeBlock)))
    #expect(!styles(t).contains(.heading(1)))
    #expect(!styles(t).contains(.bold))
}

@Test func unclosedFenceRunsToEnd() {
    #expect(has("```\nabc", run(0, 7, .codeBlock)))
}

@Test func unclosedOrMultilineBoldIsIgnored() {
    #expect(!styles("**open").contains(.bold))
    #expect(!styles("**a\nb**").contains(.bold))
}

@Test func emojiUsesUTF16Ranges() {
    #expect(has("😀 **b**", run(3, 5, .bold)))
}

@Test func syntaxRunsComeLast() {
    let s = styles("# **a**")
    let firstSyntax = s.firstIndex(of: .syntax)!
    #expect(s[firstSyntax...].allSatisfy { $0 == .syntax })
}

// MARK: Preview (⌘E): which characters get hidden or replaced

private func edit(_ loc: Int, _ len: Int, _ r: String = "") -> PreviewEdit {
    PreviewEdit(range: NSRange(location: loc, length: len), replacement: r)
}
private func edits(_ t: String) -> [PreviewEdit] { MarkdownStyler.previewEdits(in: t) }

@Test func previewHidesHeadingAndBoldMarkers() {
    #expect(edits("# Hi") == [edit(0, 2)])
    #expect(edits("a **b** c") == [edit(2, 2), edit(5, 2)])
}

@Test func previewTurnsDashesIntoBulletsAndKeepsNumbers() {
    #expect(edits("- item") == [edit(0, 1, "•")])
    #expect(edits("  * item") == [edit(2, 1, "•")])
    #expect(edits("1. one") == [])
}

@Test func previewDropsFenceLinesWithTheirNewline() {
    #expect(edits("```swift\ncode\n```") == [edit(0, 9), edit(14, 3)])
}

@Test func previewKeepsOnlyLinkText() {
    #expect(edits("[a](http://x)") == [edit(0, 1), edit(2, 11)])
}

@Test func previewHidesQuoteMarker() {
    #expect(edits("> q") == [edit(0, 2)])
}

@Test func previewEditsAreSortedAndDisjoint() {
    let e = edits("# **a** `c` [l](u)\n- x\n```\ny\n```")
    for (a, b) in zip(e, e.dropFirst()) { #expect(NSMaxRange(a.range) <= b.range.location) }
}

@Test func strikethrough() {
    #expect(has("~~a~~", run(0, 5, .strike)))
    #expect(has("~~a~~", run(0, 2, .syntax)))
    #expect(has("~~a~~", run(3, 2, .syntax)))
}

@Test func todoCheckboxes() {
    #expect(has("- [ ] a", run(2, 3, .checkbox(false))))
    #expect(has("- [x] a", run(2, 3, .checkbox(true))))
    #expect(has("- [x] done", run(6, 4, .done)))
    #expect(!styles("- [ ] a").contains(.done))
}

@Test func previewShowsCheckboxes() {
    #expect(edits("- [ ] a") == [edit(0, 5, "☐")])
    #expect(edits("  - [x] a") == [edit(2, 5, "☑")])
}

@Test func imagesAreNotLinks() {
    let t = "![cat](https://x/c.png)"
    #expect(has(t, run(2, 3, .image("https://x/c.png"))))
    #expect(!styles(t).contains { if case .link = $0 { true } else { false } })
    #expect(has(t, run(0, 2, .syntax)))
    #expect(has(t, run(5, 18, .syntax)))
}

@Test func imageTitleIsIgnoredInURL() {
    #expect(has(#"![a](p.png "Title")"#, run(2, 1, .image("p.png"))))
}

@Test func previewReplacesImageWithOnePlaceholder() {
    #expect(edits("x ![cat](https://x/c.png) y") == [edit(2, 23, "\u{FFFC}")])
}
