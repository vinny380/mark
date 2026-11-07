import AppKit
import MarkCore

@MainActor enum Theme {
    nonisolated private static func hex(_ v: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
    nonisolated private static func dynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { @Sendable in $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? hex(dark) : hex(light) }
    }
    private static func font(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static let background = dynamic(light: 0xffffff, dark: 0x0a0a0a)
    static let syntax = hex(0x888888)
    static let codeBackground = dynamic(light: 0xf5f5f5, dark: 0x171717)
    static let border = dynamic(light: 0xeaeaea, dark: 0x333333)
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

    static func apply(_ runs: [StyleRun], to storage: NSTextStorage, preview: Bool = false) {
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))
        for run in runs { apply(run.style, run.range, storage, preview) }
        storage.endEditing()
    }

    /// Read-only rendering for ⌘E: styled, with Markdown symbols removed, links clickable, images shown.
    /// `base` resolves relative image paths; `maxWidth` is the text column (wider images scale down).
    static func preview(_ markdown: String, base: URL? = nil, maxWidth: CGFloat = 720) -> NSAttributedString {
        let s = NSTextStorage(string: markdown)
        let runs = MarkdownStyler.runs(in: markdown)
        apply(runs, to: s, preview: true)
        for e in MarkdownStyler.previewEdits(in: markdown).reversed() {
            s.replaceCharacters(in: e.range, with: e.replacement) // keeps the attributes of the replaced text
        }
        let images: [(alt: String, src: String)] = runs.compactMap {
            guard case .image(let src) = $0.style else { return nil }
            return ((markdown as NSString).substring(with: $0.range), src)
        }
        let ns = s.string as NSString
        var slots: [Int] = []
        for i in 0..<ns.length where ns.character(at: i) == 0xFFFC { slots.append(i) }
        // ponytail: a literal U+FFFC typed in the source would desync slots from images; then images are skipped.
        guard slots.count == images.count else { return s }
        for (at, img) in zip(slots, images).reversed() {
            let here = NSRange(location: at, length: 1)
            if let url = imageURL(img.src, base: base), let image = Images.image(url) {
                let a = NSTextAttachment()
                let size = fit(image.size, maxWidth)
                a.image = rounded(image, size)
                a.bounds = CGRect(origin: .zero, size: size)
                s.replaceCharacters(in: here, with: NSAttributedString(attachment: a))
                let p = NSMutableParagraphStyle()
                p.paragraphSpacing = 8 // the 1.5 line height would add half an image of air
                s.addAttribute(.paragraphStyle, value: p, range: ns.paragraphRange(for: here))
            } else {
                s.replaceCharacters(in: here, with: img.alt.isEmpty ? "Image" : img.alt) // loading, missing or unsupported
            }
        }
        return s
    }

    private static func fit(_ size: CGSize, _ maxWidth: CGFloat) -> CGSize {
        guard size.width > maxWidth, size.width > 0 else { return size }
        return CGSize(width: maxWidth, height: (size.height * maxWidth / size.width).rounded())
    }

    private static func rounded(_ image: NSImage, _ size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { r in
            NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).addClip()
            image.draw(in: r)
            return true
        }
    }

    private static func apply(_ style: MarkdownStyle, _ r: NSRange, _ s: NSTextStorage, _ preview: Bool) {
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
        case .image:
            s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
        case .link(let url):
            s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            if preview, let u = URL(string: url) { s.addAttribute(.link, value: u, range: r) } // editing mode: clicks place the cursor
        case .strike:
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        case .done:
            s.addAttributes([.foregroundColor: NSColor.tertiaryLabelColor,
                             .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: r)
        case .listMarker, .checkbox, .syntax:
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
