import Foundation

private let markdownExtensions: Set<String> = ["md", "markdown"]

/// Markdown files directly inside `dir` (not hidden, not folders), newest first.
public func markdownFiles(in dir: URL) -> [URL] {
    let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
    let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
    func modified(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
    return urls
        .filter { markdownExtensions.contains($0.pathExtension.lowercased()) && ((try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false) }
        .sorted { modified($0) > modified($1) }
}

private let systemRoots: Set<Substring> = ["System", "usr", "opt", "private", "bin", "sbin", "Library", "cores"]
private let bundleSuffixes = [".app", ".framework", ".bundle", ".xcarchive"]

/// Paths a person never means when searching their notes: OS/system folders, app bundles,
/// dependencies, caches, build output, hidden folders.
public func isNoisePath(_ path: String) -> Bool {
    let dirs = path.split(separator: "/").dropLast()
    if let root = dirs.first, systemRoots.contains(root) { return true }
    return dirs.contains { d in
        d.hasPrefix(".") || d == "node_modules" || d == "Library" || d == "DerivedData" || d == "Pods"
            || bundleSuffixes.contains { d.hasSuffix($0) }
    }
}

/// Folder of `url` for display, with the home directory shortened to `~`.
public func displayPath(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
    let dir = url.deletingLastPathComponent().standardizedFileURL.path
    let h = home.standardizedFileURL.path
    if dir == h { return "~" }
    if dir.hasPrefix(h + "/") { return "~" + dir.dropFirst(h.count) }
    return dir
}
