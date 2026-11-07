import Foundation

/// Creates an empty `Untitled.md` (or `Untitled N.md`) in `directory`. Never overwrites.
public func createUntitledMarkdown(in directory: URL) throws -> URL {
    var n = 1
    while true {
        let name = n == 1 ? "Untitled.md" : "Untitled \(n).md"
        let url = directory.appendingPathComponent(name)
        do {
            try Data().write(to: url, options: .withoutOverwriting)
            return url
        } catch CocoaError.fileWriteFileExists {
            n += 1
        }
    }
}

/// `mark://new?dir=<path>` — how the sandboxed Finder extension asks the app to create a file.
public func newFileRequestURL(directory: URL) -> URL {
    var c = URLComponents()
    c.scheme = "mark"
    c.host = "new"
    c.queryItems = [URLQueryItem(name: "dir", value: directory.path)]
    return c.url!
}

/// The target directory of a `mark://new` request, if it names an existing directory.
public func directory(fromNewFileRequest url: URL) -> URL? {
    guard url.scheme == "mark", url.host == "new",
          let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
              .queryItems?.first(where: { $0.name == "dir" })?.value
    else { return nil }
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
}
