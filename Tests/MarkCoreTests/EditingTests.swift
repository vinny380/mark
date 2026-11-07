import Foundation
import Testing
@testable import MarkCore

/// Applies an edit and renders the result with the selection marked: "a [b] c" = "b" selected, "a | c" = caret.
private func run(_ text: String, _ edit: (String, NSRange) -> TextEdit?) -> String? {
    let (plain, sel) = parse(text)
    guard let e = edit(plain, sel) else { return nil }
    let out = (plain as NSString).replacingCharacters(in: e.range, with: e.replacement) as NSString
    let s = e.selection
    if s.length == 0 { return out.replacingCharacters(in: NSRange(location: s.location, length: 0), with: "|") }
    return out.replacingCharacters(in: s, with: "[" + out.substring(with: s) + "]")
}
private func parse(_ marked: String) -> (String, NSRange) {
    let ns = marked as NSString
    let caret = ns.range(of: "|")
    if caret.location != NSNotFound { return (ns.replacingCharacters(in: caret, with: ""), NSRange(location: caret.location, length: 0)) }
    let open = ns.range(of: "["), close = ns.range(of: "]", options: .backwards)
    let inner = ns.substring(with: NSRange(location: open.location + 1, length: close.location - open.location - 1))
    let plain = ns.replacingCharacters(in: NSRange(location: open.location, length: close.location - open.location + 1), with: inner)
    return (plain, NSRange(location: open.location, length: (inner as NSString).length))
}

// ⌘B / ⌘I / ⌘⇧X / ⌘⇧E
@Test func wrapsSelection() { #expect(run("a [b] c") { toggleWrap($0, $1, "**") } == "a **[b]** c") }
@Test func unwrapsWhenMarkersAreOutsideSelection() { #expect(run("a **[b]** c") { toggleWrap($0, $1, "**") } == "a [b] c") }
@Test func unwrapsWhenMarkersAreSelected() { #expect(run("a [**b**] c") { toggleWrap($0, $1, "**") } == "a [b] c") }
@Test func emptySelectionInsertsPairWithCaretInside() { #expect(run("a |") { toggleWrap($0, $1, "**") } == "a **|**") }
@Test func italicInsideBoldWrapsInsteadOfBreakingBold() { #expect(run("**[b]**") { toggleWrap($0, $1, "*") } == "***[b]***") }
@Test func italicToggleOffInsideBoldItalic() { #expect(run("***[b]***") { toggleWrap($0, $1, "*") } == "**[b]**") }
@Test func strikeAndCodeUseTheSameToggle() {
    #expect(run("[x]") { toggleWrap($0, $1, "~~") } == "~~[x]~~")
    #expect(run("`[x]`") { toggleWrap($0, $1, "`") } == "[x]")
}

// ⌘K and paste-URL-on-selection
@Test func linkWrapsSelectionAndPutsCaretInParens() { #expect(run("see [docs] now") { makeLink($0, $1) } == "see [docs](|) now") }
@Test func linkOnSelectedURLPutsCaretInBrackets() { #expect(run("[https://x.com]") { makeLink($0, $1) } == "[|](https://x.com)") }
@Test func linkWithNoSelection() { #expect(run("a |") { makeLink($0, $1) } == "a [|]()") }
@Test func pastingURLOverSelectionMakesLink() {
    #expect(run("[docs]") { linkPaste($0, $1, "https://x.com") } == "[docs](https://x.com)|")
    #expect(run("[docs]") { linkPaste($0, $1, "not a url") } == nil)
    #expect(run("docs|") { linkPaste($0, $1, "https://x.com") } == nil)
}

// Return / Tab in lists
@Test func returnContinuesBullets() { #expect(run("- a|") { continueList($0, $1) } == "- a\n- |") }
@Test func returnContinuesIndentedStarBullets() { #expect(run("  * a|") { continueList($0, $1) } == "  * a\n  * |") }
@Test func returnIncrementsNumbers() { #expect(run("9. a|") { continueList($0, $1) } == "9. a\n10. |") }
@Test func returnStartsUncheckedTodo() { #expect(run("- [x] done|") { continueList($0, $1) } == "- [x] done\n- [ ] |") }
@Test func returnContinuesQuotes() { #expect(run("> q|") { continueList($0, $1) } == "> q\n> |") }
@Test func returnOnEmptyItemEndsList() { #expect(run("- a\n- |") { continueList($0, $1) } == "- a\n|") }
@Test func returnOutsideListIsNormal() { #expect(run("plain|") { continueList($0, $1) } == nil) }
@Test func returnInMiddleOfItemSplitsIt() { #expect(run("- ab|cd") { continueList($0, $1) } == "- ab\n- |cd") }
@Test func tabIndentsAndShiftTabOutdents() {
    #expect(run("- a|") { indentList($0, $1, outdent: false) } == "  - a|")
    #expect(run("  - a|") { indentList($0, $1, outdent: true) } == "- a|")
    #expect(run("1. a|") { indentList($0, $1, outdent: false) } == "   1. a|")
    #expect(run("plain|") { indentList($0, $1, outdent: false) } == nil)
}

// ⌘⌥1/2/3/0
@Test func setsHeadingLevel() {
    #expect(run("ti|tle") { setHeading($0, $1, level: 2) } == "## ti|tle")
    #expect(run("# ti|tle") { setHeading($0, $1, level: 3) } == "### ti|tle")
    #expect(run("### ti|tle") { setHeading($0, $1, level: 0) } == "ti|tle")
    #expect(run("a\nb|") { setHeading($0, $1, level: 1) } == "a\n# b|")
}

// ⌘↩
@Test func togglesTodo() {
    #expect(run("- [ ] a|") { toggleTodo($0, $1) } == "- [x] a|")
    #expect(run("- [x] a|") { toggleTodo($0, $1) } == "- [ ] a|")
    #expect(run("- a|") { toggleTodo($0, $1) } == "- [ ] a|")
    #expect(run("a|") { toggleTodo($0, $1) } == "- [ ] a|")
}
