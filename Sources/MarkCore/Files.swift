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

/// Subfolders worth browsing into from ⌘P: not hidden, not app bundles, not node_modules. Finder order.
/// (Name-based only: when you browse on purpose, system folders like /usr stay visible, as in Finder.)
public func browsableFolders(in dir: URL) -> [URL] {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
    let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
    return urls
        .filter { url in
            let v = try? url.resourceValues(forKeys: Set(keys)), name = url.lastPathComponent
            return v?.isDirectory == true && v?.isPackage != true
                && name != "node_modules" && !bundleSuffixes.contains { name.hasSuffix($0) }
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}

public func parentFolder(of dir: URL) -> URL {
    dir.path == "/" ? dir : dir.deletingLastPathComponent()
}

public struct FuzzyMatch: Equatable, Sendable {
    public let score: Int
    /// UTF-16 offsets of the matched characters in the candidate (for highlighting).
    public let positions: [Int]
}

private let separators = Set(" -_./()[]".utf16)

/// Subsequence match ("wkn" → "Weekly notes"). Rewards word starts and runs, punishes gaps and late starts.
/// ponytail: greedy after the first letter, tries every start; good enough for file names.
public func fuzzyMatch(_ query: String, _ candidate: String) -> FuzzyMatch? {
    let q = Array(query.lowercased().utf16), c = Array(candidate.lowercased().utf16)
    guard let first = q.first else { return FuzzyMatch(score: 0, positions: []) }
    var best: FuzzyMatch?
    for start in c.indices where c[start] == first {
        var pos = [start], ci = start + 1
        for ch in q.dropFirst() {
            while ci < c.count, c[ci] != ch { ci += 1 }
            if ci == c.count { return best } // later starts have even fewer letters left
            pos.append(ci)
            ci += 1
        }
        var score = -(start / 3)
        for (i, p) in pos.enumerated() {
            score += 1
            if p == 0 || separators.contains(c[p - 1]) { score += 6 }
            if i > 0 { score += p == pos[i - 1] + 1 ? 8 : -min(p - pos[i - 1] - 1, 5) }
        }
        if score > best?.score ?? .min { best = FuzzyMatch(score: score, positions: pos) }
    }
    return best
}

/// Where a Markdown image points: http(s), file:, absolute path, or a path relative to the document's folder.
/// nil for anything else (javascript:, data:, relative paths in an unsaved document).
public func imageURL(_ src: String, base: URL?) -> URL? {
    let lower = src.lowercased()
    if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return URL(string: src) }
    if lower.hasPrefix("file://") { return URL(string: src).flatMap { $0.isFileURL ? $0 : nil } }
    if lower.range(of: #"^[a-z][a-z0-9+.-]*:"#, options: .regularExpression) != nil { return nil } // other schemes
    let path = src.removingPercentEncoding ?? src
    if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
    return base.map { $0.appendingPathComponent(path).standardizedFileURL } // works with or without a trailing slash
}
