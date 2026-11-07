import Foundation

public enum DiagramKind: Hashable, Sendable { case mermaid, math(display: Bool) }

public enum MarkdownStyle: Equatable, Sendable {
    case heading(Int), bold, italic, strike, code, codeBlock, quote, link(String), image(String), diagram(DiagramKind, String), listMarker, checkbox(Bool), done, syntax
}

/// Preview (⌘E): replace `range` of the source with `replacement` ("" = hide).
public struct PreviewEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public init(range: NSRange, replacement: String) { self.range = range; self.replacement = replacement }
}

public struct StyleRun: Equatable, Sendable {
    public let range: NSRange
    public let style: MarkdownStyle
    public init(range: NSRange, style: MarkdownStyle) { self.range = range; self.style = style }
}

/// Turns Markdown source into style runs (UTF-16 ranges). Apply in order; `.syntax` runs come last.
/// ponytail: line-based regex tokenizer, not a CommonMark parser. Nested/edge-case emphasis may look off.
public enum MarkdownStyler {
    private static func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    private static let heading = rx(#"^(#{1,6}) "#)
    private static let hr = rx(#"^ {0,3}([-*_])( *\1){2,} *$"#)
    private static let list = rx(#"^\s*([-*+]|\d+\.)\s"#)
    private static let code = rx(#"`[^`]+`"#)
    private static let bold = rx(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    // $…$ inline math: no space just inside the dollars, no digit/word right after ("$5 and $10" is money)
    private static let inlineMath = rx(#"(?<![\\$\w])\$([^\s$](?:[^$\n]*?[^\s$\\])?)\$(?![\d$\w])"#)
    private static let strike = rx(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let checkbox = rx(#"^\s*[-*+] (\[([ xX])\])"#)
    private static let italic = rx(#"(?<![*_\w])([*_])(?![\s*_])(.+?)(?<![\s*_])\1(?![*_\w])"#)
    private static let link = rx(#"(?<!!)\[([^\]]+)\]\(([^)]*)\)"#)
    private static let image = rx(#"!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#)

    public static func runs(in text: String) -> [StyleRun] {
        let ns = text as NSString
        var styled: [StyleRun] = [], syntax: [StyleRun] = []
        var fenceStart: Int?, fenceInner = 0, fenceLang = "", fenceIsDollars = false

        func add(_ loc: Int, _ len: Int, _ s: MarkdownStyle) {
            let r = StyleRun(range: NSRange(location: loc, length: len), style: s)
            if s == .syntax { syntax.append(r) } else { styled.append(r) }
        }

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { sub, lineRange, _, _ in
            guard let line = sub else { return }
            let base = lineRange.location, len = lineRange.length
            let whole = NSRange(location: 0, length: len)

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if fenceStart == nil, trimmed.count > 4, trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$") { // $$x$$ on one line
                add(base, len, .diagram(.math(display: true), String(trimmed.dropFirst(2).dropLast(2))))
                add(base, len, .code)
                return
            }
            let opensOrCloses = fenceStart == nil ? (line.hasPrefix("```") || trimmed == "$$")
                                                  : (fenceIsDollars ? trimmed == "$$" : line.hasPrefix("```"))
            if opensOrCloses {
                add(base, len, .syntax)
                if let start = fenceStart {
                    let end = NSMaxRange(lineRange)
                    add(start, end - start, .codeBlock)
                    let inner = ns.substring(with: NSRange(location: fenceInner, length: max(0, base - 1 - fenceInner)))
                    if fenceLang == "mermaid" { add(start, end - start, .diagram(.mermaid, inner)) }
                    if fenceLang == "math" || fenceIsDollars { add(start, end - start, .diagram(.math(display: true), inner)) }
                    fenceStart = nil
                } else {
                    fenceStart = base
                    fenceInner = NSMaxRange(lineRange) + 1
                    fenceIsDollars = trimmed == "$$"
                    fenceLang = fenceIsDollars ? "" : String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
                }
                return
            }
            if fenceStart != nil { return }

            if let m = heading.firstMatch(in: line, range: whole) {
                add(base, len, .heading(m.range(at: 1).length))
                add(base, m.range.length, .syntax)
            } else if line.hasPrefix(">") {
                add(base, len, .quote)
                add(base, line.hasPrefix("> ") ? 2 : 1, .syntax)
            } else if hr.firstMatch(in: line, range: whole) != nil {
                add(base, len, .syntax)
                return
            } else if let m = list.firstMatch(in: line, range: whole) {
                let marker = m.range(at: 1)
                add(base + marker.location, marker.length, .listMarker)
                if let c = checkbox.firstMatch(in: line, range: whole) {
                    let box = c.range(at: 1), done = (line as NSString).substring(with: c.range(at: 2)) != " "
                    add(base + box.location, box.length, .checkbox(done))
                    let rest = NSMaxRange(box) + 1
                    if done, rest < len { add(base + rest, len - rest, .done) }
                }
            }

            let codeSpans = code.matches(in: line, range: whole).map(\.range)
            for r in codeSpans {
                add(base + r.location, r.length, .code)
                add(base + r.location, 1, .syntax)
                add(base + NSMaxRange(r) - 1, 1, .syntax)
            }
            func outsideCode(_ r: NSRange) -> Bool { !codeSpans.contains { NSIntersectionRange($0, r).length > 0 } }
            var mathSpans: [NSRange] = []
            for m in inlineMath.matches(in: line, range: whole) where outsideCode(m.range) {
                mathSpans.append(m.range)
                add(base + m.range.location, m.range.length, .diagram(.math(display: false), (line as NSString).substring(with: m.range(at: 1))))
                add(base + m.range.location, 1, .syntax)
                add(base + NSMaxRange(m.range) - 1, 1, .syntax)
            }
            func outsideCodeAndMath(_ r: NSRange) -> Bool { outsideCode(r) && !mathSpans.contains { NSIntersectionRange($0, r).length > 0 } }

            for (regex, style, delim) in [(bold, MarkdownStyle.bold, 2), (italic, .italic, 1), (strike, .strike, 2)] {
                for m in regex.matches(in: line, range: whole) where outsideCodeAndMath(m.range) {
                    add(base + m.range.location, m.range.length, style)
                    add(base + m.range.location, delim, .syntax)
                    add(base + NSMaxRange(m.range) - delim, delim, .syntax)
                }
            }
            for m in image.matches(in: line, range: whole) where outsideCode(m.range) {
                let alt = m.range(at: 1)
                add(base + m.range.location, 2, .syntax)
                add(base + alt.location, alt.length, .image((line as NSString).substring(with: m.range(at: 2))))
                add(base + NSMaxRange(alt), NSMaxRange(m.range) - NSMaxRange(alt), .syntax)
            }
            for m in link.matches(in: line, range: whole) where outsideCode(m.range) {
                let label = m.range(at: 1)
                add(base + m.range.location, 1, .syntax)
                add(base + label.location, label.length, .link((line as NSString).substring(with: m.range(at: 2))))
                add(base + NSMaxRange(label), NSMaxRange(m.range) - NSMaxRange(label), .syntax)
            }
        }
        if let start = fenceStart { add(start, ns.length - start, .codeBlock) }
        return styled + syntax
    }

    /// What Preview hides: every syntax marker (fence lines with their newline), unordered list markers → "•".
    /// Sorted, non-overlapping; apply in reverse.
    public static func previewEdits(in text: String) -> [PreviewEdit] {
        let ns = text as NSString
        var edits: [PreviewEdit] = []
        let all = runs(in: text)
        var boxes: [Int: StyleRun] = [:] // checkbox runs by location, so "- [ ]" becomes one symbol
        var syntaxAt: [Int: NSRange] = [:]
        for run in all {
            if case .checkbox = run.style { boxes[run.range.location] = run }
            if run.style == .syntax { syntaxAt[run.range.location] = run.range }
        }
        for run in all {
            let s = ns.substring(with: run.range)
            switch run.style {
            case .syntax:
                var r = run.range
                if s.hasPrefix("```"), NSMaxRange(r) < ns.length, ns.character(at: NSMaxRange(r)) == 10 { r.length += 1 }
                edits.append(PreviewEdit(range: r, replacement: ""))
            case .diagram:
                edits.append(PreviewEdit(range: run.range, replacement: "\u{FFFC}")) // the app swaps in the rendered diagram
            case .image:
                // whole "![alt](url)" → one object-replacement char; the app swaps in the picture
                let start = run.range.location - 2, end = syntaxAt[NSMaxRange(run.range)].map(NSMaxRange) ?? NSMaxRange(run.range)
                edits.append(PreviewEdit(range: NSRange(location: start, length: end - start), replacement: "\u{FFFC}"))
            case .listMarker where !(s.first?.isNumber ?? false):
                if let box = boxes[NSMaxRange(run.range) + 1], case .checkbox(let done) = box.style {
                    let r = NSRange(location: run.range.location, length: NSMaxRange(box.range) - run.range.location)
                    edits.append(PreviewEdit(range: r, replacement: done ? "☑" : "☐"))
                } else {
                    edits.append(PreviewEdit(range: run.range, replacement: "•"))
                }
            default:
                break
            }
        }
        edits.sort { ($0.range.location, -$0.range.length) < ($1.range.location, -$1.range.length) } // widest wins a tie
        var out: [PreviewEdit] = []
        for e in edits where out.last.map({ NSMaxRange($0.range) <= e.range.location }) ?? true { out.append(e) }
        return out
    }
}

public struct Heading: Equatable, Sendable {
    public let title: String
    public let level: Int
    /// UTF-16 offset of the heading line in the source.
    public let location: Int
    public init(title: String, level: Int, location: Int) { self.title = title; self.level = level; self.location = location }
}

/// The document's headings, in order (⌘P "#"). Headings inside code blocks don't count.
public func outline(_ text: String) -> [Heading] {
    let ns = text as NSString
    return MarkdownStyler.runs(in: text).compactMap { run in
        guard case .heading(let level) = run.style else { return nil }
        let title = ns.substring(with: run.range)
            .replacingOccurrences(of: #"^#{1,6}\s+|\s+#+\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return Heading(title: title, level: level, location: run.range.location)
    }
}
