import AppKit

/// Images for Preview. Files load on demand; web images load in the background once per session,
/// then `didLoad` fires so open previews re-render.
@MainActor enum Images {
    static let didLoad = Notification.Name("MarkImageDidLoad")
    // ponytail: unbounded in-memory cache for the app's lifetime; add NSCache if huge image docs show up.
    private static var web: [URL: NSImage] = [:]
    private static var pending: Set<URL> = []
    private static var local: [URL: (modified: Date, image: NSImage)] = [:]

    static func image(_ url: URL) -> NSImage? {
        if url.isFileURL {
            // Re-read only when the file changed: edit mode asks on every keystroke, and you may be editing the picture.
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
            if let hit = local[url], hit.modified == modified { return hit.image }
            let image = NSImage(contentsOf: url)
            local[url] = image.map { (modified, $0) }
            return image
        }
        if let cached = web[url] { return cached }
        guard pending.insert(url).inserted else { return nil } // loading, or failed earlier this session
        Task {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let image = NSImage(data: data) else { return }
            web[url] = image
            NotificationCenter.default.post(name: didLoad, object: nil)
        }
        return nil
    }
}
