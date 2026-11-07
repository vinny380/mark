import AppKit
import MarkCore

@MainActor enum Theme {
    private static func hex(_ v: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
    private static func dynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? hex(dark) : hex(light) }
    }
    private static func font(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static let background = dynamic(light: 0xffffff, dark: 0x0a0a0a)
    static let syntax = hex(0x888888)
    static let codeBackground = dynamic(light: 0xf5f5f5, dark: 0x171717)
    static let headingSizes: [CGFloat] = [28, 22, 18, 16, 15, 15]

    static let body = font("Geist-Regular", 15)
    static let mono = NSFont(name: "GeistMono-Regular", size: 13.5) ?? .monospacedSystemFont(ofSize: 13.5, weight: .regular)
    static let paragraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = 1.5
        return p
    }()

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    static func apply(_ runs: [StyleRun], to storage: NSTextStorage) {
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
        for run in runs { apply(run.style, run.range, storage) }
        storage.endEditing()
    }

    private static func apply(_ style: MarkdownStyle, _ r: NSRange, _ s: NSTextStorage) {
        switch style {
        case .heading(let level):
            s.addAttribute(.font, value: font("Geist-SemiBold", headingSizes[level - 1], .semibold), range: r)
        case .bold:
            refont(r, s) { font("Geist-Bold", $0.pointSize, .bold) }
        case .italic:
            refont(r, s) { NSFont(name: "Geist-Italic", size: $0.pointSize) ?? NSFontManager.shared.convert($0, toHaveTrait: .italicFontMask) }
        case .code, .codeBlock:
            s.addAttributes([.font: mono, .backgroundColor: codeBackground], range: r)
        case .quote:
            s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
        case .link:
            s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        case .syntax:
            s.addAttribute(.foregroundColor, value: syntax, range: r)
        }
    }

    /// Swap the font face but keep the size already set (so **bold** inside a heading stays heading-sized).
    private static func refont(_ r: NSRange, _ s: NSTextStorage, _ make: (NSFont) -> NSFont) {
        s.enumerateAttribute(.font, in: r) { value, sub, _ in
            s.addAttribute(.font, value: make(value as? NSFont ?? body), range: sub)
        }
    }
}
