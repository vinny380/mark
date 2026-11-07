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
    #expect(has("* item", run(0, 1, .syntax)))
    #expect(!styles("* item").contains(.italic))
    #expect(has("1. one", run(0, 2, .syntax)))
}

@Test func inlineCode() {
    #expect(has("`c`", run(0, 3, .code)))
    #expect(has("`c`", run(0, 1, .syntax)))
    #expect(has("`c`", run(2, 1, .syntax)))
}

@Test func link() {
    #expect(has("[a](http://x)", run(1, 1, .link)))
    #expect(has("[a](http://x)", run(0, 1, .syntax)))
    #expect(has("[a](http://x)", run(2, 11, .syntax)))
}

@Test func quote() {
    #expect(has("> q", run(0, 3, .quote)))
    #expect(has("> q", run(0, 1, .syntax)))
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
