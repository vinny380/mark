import Foundation

/// `![alt](path)` that survives spaces, parentheses and % in file names.
public func imageMarkdown(alt: String, path: String) -> String {
    let isWeb = path.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*:"#, options: .regularExpression) != nil
    var p = isWeb ? path : path.replacingOccurrences(of: "%", with: "%25") // web URLs are already encoded
    for (c, e) in [(" ", "%20"), ("(", "%28"), (")", "%29")] { p = p.replacingOccurrences(of: c, with: e) }
    let cleanAlt = alt.filter { $0 != "[" && $0 != "]" }
    return "![\(cleanAlt)](\(p))"
}

/// File name for a copied image: spaces → dashes, then "-2", "-3"… until `exists` says it's free.
public func assetName(for original: String, exists: (String) -> Bool) -> String {
    let tidy = original.replacingOccurrences(of: " ", with: "-")
    let ext = (tidy as NSString).pathExtension, stem = (tidy as NSString).deletingPathExtension
    var name = tidy, n = 2
    while exists(name) {
        name = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
        n += 1
    }
    return name
}

/// `file`'s path relative to `dir`, if it lives inside it.
public func relativePath(of file: URL, inside dir: URL) -> String? {
    let f = file.standardizedFileURL.path, d = dir.standardizedFileURL.path
    return f.hasPrefix(d + "/") ? String(f.dropFirst(d.count + 1)) : nil
}

/// Insert `block` as its own line at `at` (adds a newline before if mid-line, always one after).
public func insertBlock(_ text: String, at: Int, _ block: String) -> TextEdit {
    let ns = text as NSString
    let before = at > 0 && ns.character(at: at - 1) != 10 ? "\n" : ""
    let insert = before + block + "\n"
    return TextEdit(range: NSRange(location: at, length: 0), replacement: insert,
                    selection: NSRange(location: at + (insert as NSString).length, length: 0))
}
