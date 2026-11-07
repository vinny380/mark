import Foundation

/// One replacement in the source plus where the selection ends up. Ranges are UTF-16.
public struct TextEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange
    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range; self.replacement = replacement; self.selection = selection
    }
}

private func len(_ s: String) -> Int { (s as NSString).length }
private func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
private let listItem = rx(#"^(\s*)([-*+]|\d+[.)])( \[[ xX]\])? "#)
private let quoteItem = rx(#"^(\s*)> ?"#)
private let headingPrefix = rx(#"^#{1,6} "#)
private let todoItem = rx(#"^\s*[-*+] \[([ xX])\] "#)
private let bulletItem = rx(#"^\s*[-*+] "#)
private let indentPrefix = rx(#"^\s*"#)

private func isURL(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return !t.contains(where: \.isWhitespace) && ["http://", "https://", "mailto:"].contains { t.lowercased().hasPrefix($0) }
}

/// Line containing the caret, without its newline.
private func line(_ ns: NSString, _ at: Int) -> NSRange {
    var start = 0, end = 0, contentsEnd = 0
    ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: at, length: 0))
    return NSRange(location: start, length: contentsEnd - start)
}

/// Where `sel` lands after `r` is replaced by `newLength` characters.
private func adjust(_ sel: NSRange, _ r: NSRange, _ newLength: Int) -> NSRange {
    func map(_ p: Int) -> Int {
        if p <= r.location { return p }
        if p >= NSMaxRange(r) { return p + newLength - r.length }
        return r.location + newLength
    }
    let a = map(sel.location), b = map(NSMaxRange(sel))
    return NSRange(location: a, length: b - a)
}

/// Replace the line prefix matched by `regex` (empty match if none) with `prefix`.
private func replacePrefix(_ ns: NSString, _ sel: NSRange, _ regex: NSRegularExpression, _ prefix: (NSTextCheckingResult?) -> String) -> TextEdit {
    let l = line(ns, sel.location)
    let m = regex.firstMatch(in: ns as String, range: l)
    let old = NSRange(location: l.location, length: m?.range.length ?? 0)
    let p = prefix(m)
    return TextEdit(range: old, replacement: p, selection: adjust(sel, old, len(p)))
}

/// ⌘B / ⌘I / ⌘⇧X / ⌘⇧E: wrap the selection in `marker`, or unwrap if it already is.
public func toggleWrap(_ text: String, _ sel: NSRange, _ marker: String) -> TextEdit {
    let ns = text as NSString, m = len(marker)
    let unit = (marker as NSString).substring(to: 1)
    func run(from i: Int, step: Int) -> Int { // how many marker chars sit next to the selection
        var n = 0, j = i
        while j >= 0, j < ns.length, ns.substring(with: NSRange(location: j, length: 1)) == unit { n += 1; j += step }
        return n
    }
    // Single-char markers share their character with longer ones (* vs **): odd run = italic is on.
    func present(_ r: Int) -> Bool { m == 1 ? r % 2 == 1 : r >= m }

    if present(run(from: sel.location - 1, step: -1)), present(run(from: NSMaxRange(sel), step: 1)) {
        let r = NSRange(location: sel.location - m, length: sel.length + 2 * m)
        return TextEdit(range: r, replacement: ns.substring(with: sel), selection: NSRange(location: r.location, length: sel.length))
    }
    let selected = ns.substring(with: sel) as NSString
    func runInside(atStart: Bool) -> Int {
        var n = 0
        while n < selected.length {
            let i = atStart ? n : selected.length - 1 - n
            guard selected.substring(with: NSRange(location: i, length: 1)) == unit else { break }
            n += 1
        }
        return n
    }
    if sel.length > 2 * m, present(runInside(atStart: true)), present(runInside(atStart: false)) {
        let inner = selected.substring(with: NSRange(location: m, length: sel.length - 2 * m))
        return TextEdit(range: sel, replacement: inner, selection: NSRange(location: sel.location, length: len(inner)))
    }
    return TextEdit(range: sel, replacement: marker + (selected as String) + marker,
                    selection: NSRange(location: sel.location + m, length: sel.length))
}

/// ⌘K: `[selection](|)`, or `[|](url)` when the selection is a URL.
public func makeLink(_ text: String, _ sel: NSRange) -> TextEdit {
    let s = (text as NSString).substring(with: sel)
    if s.isEmpty { return TextEdit(range: sel, replacement: "[]()", selection: NSRange(location: sel.location + 1, length: 0)) }
    if isURL(s) { return TextEdit(range: sel, replacement: "[](\(s))", selection: NSRange(location: sel.location + 1, length: 0)) }
    return TextEdit(range: sel, replacement: "[\(s)]()", selection: NSRange(location: sel.location + len(s) + 3, length: 0))
}

/// Pasting a URL over selected text makes it a link.
public func linkPaste(_ text: String, _ sel: NSRange, _ pasted: String) -> TextEdit? {
    let s = (text as NSString).substring(with: sel)
    guard sel.length > 0, isURL(pasted), !isURL(s) else { return nil }
    let r = "[\(s)](\(pasted.trimmingCharacters(in: .whitespacesAndNewlines)))"
    return TextEdit(range: sel, replacement: r, selection: NSRange(location: sel.location + len(r), length: 0))
}

/// Return inside a list or quote: continue it, or end it if the item is empty. nil = normal newline.
public func continueList(_ text: String, _ sel: NSRange) -> TextEdit? {
    let ns = text as NSString
    let l = line(ns, sel.location)
    guard let m = listItem.firstMatch(in: text, range: l) ?? quoteItem.firstMatch(in: text, range: l),
          sel.location >= NSMaxRange(m.range) else { return nil }
    let rest = ns.substring(with: NSRange(location: NSMaxRange(m.range), length: NSMaxRange(l) - NSMaxRange(m.range)))
    if rest.trimmingCharacters(in: .whitespaces).isEmpty { // empty item → end the list
        return TextEdit(range: l, replacement: "", selection: NSRange(location: l.location, length: 0))
    }
    let indent = ns.substring(with: m.range(at: 1))
    var prefix = indent + "> "
    if m.numberOfRanges > 2, m.range(at: 2).location != NSNotFound {
        var marker = ns.substring(with: m.range(at: 2))
        if let n = Int(marker.dropLast()) { marker = "\(n + 1)\(marker.last!)" }
        prefix = indent + marker + (m.range(at: 3).location != NSNotFound ? " [ ]" : "") + " "
    }
    let insert = "\n" + prefix
    return TextEdit(range: sel, replacement: insert, selection: NSRange(location: sel.location + len(insert), length: 0))
}

/// Tab / ⇧Tab on a list item: indent by the marker's width. nil = not a list item.
public func indentList(_ text: String, _ sel: NSRange, outdent: Bool) -> TextEdit? {
    let ns = text as NSString
    let l = line(ns, sel.location)
    guard let m = listItem.firstMatch(in: text, range: l) else { return nil }
    let unit = Int(ns.substring(with: m.range(at: 2)).dropLast()) != nil ? m.range(at: 2).length + 1 : 2
    let current = m.range(at: 1).length
    let newIndent = outdent ? max(0, current - unit) : current + unit
    if newIndent == current { return nil }
    return replacePrefix(ns, sel, indentPrefix) { _ in String(repeating: " ", count: newIndent) }
}

/// ⌘⌥1/2/3 (0 = plain text): set the current line's heading level.
public func setHeading(_ text: String, _ sel: NSRange, level: Int) -> TextEdit {
    replacePrefix(text as NSString, sel, headingPrefix) { _ in level > 0 ? String(repeating: "#", count: level) + " " : "" }
}

/// ⌘↩: check/uncheck a to-do; turn a bullet or plain line into one.
public func toggleTodo(_ text: String, _ sel: NSRange) -> TextEdit {
    let ns = text as NSString
    let l = line(ns, sel.location)
    if let m = todoItem.firstMatch(in: text, range: l) {
        let box = m.range(at: 1)
        let flipped = ns.substring(with: box) == " " ? "x" : " "
        return TextEdit(range: box, replacement: flipped, selection: sel)
    }
    if let m = bulletItem.firstMatch(in: text, range: l) {
        let at = NSRange(location: NSMaxRange(m.range), length: 0)
        return TextEdit(range: at, replacement: "[ ] ", selection: adjust(sel, at, 4))
    }
    return replacePrefix(ns, sel, indentPrefix) { m in ns.substring(with: m!.range) + "- [ ] " }
}

/// ⌥↑ / ⌥↓: swap the selected line(s) with the line above/below. nil at the document edge.
public func moveLines(_ text: String, _ sel: NSRange, up: Bool) -> TextEdit? {
    let ns = text as NSString
    let block = ns.lineRange(for: sel)
    var b = ns.substring(with: block)
    let offset = sel.location - block.location
    if up {
        guard block.location > 0 else { return nil }
        let prev = ns.lineRange(for: NSRange(location: block.location - 1, length: 0))
        var p = ns.substring(with: prev)
        if !b.hasSuffix("\n") { b += "\n"; p.removeLast() } // block was the last line, without a newline
        return TextEdit(range: NSRange(location: prev.location, length: NSMaxRange(block) - prev.location), replacement: b + p,
                        selection: NSRange(location: prev.location + offset, length: sel.length))
    }
    guard NSMaxRange(block) < ns.length else { return nil }
    let next = ns.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
    var n = ns.substring(with: next)
    if !n.hasSuffix("\n") { n += "\n"; b.removeLast() }
    return TextEdit(range: NSRange(location: block.location, length: NSMaxRange(next) - block.location), replacement: n + b,
                    selection: NSRange(location: block.location + len(n) + offset, length: sel.length))
}
