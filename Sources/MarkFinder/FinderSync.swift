import Cocoa
import FinderSync
import MarkCore

/// Adds "New Markdown File" to Finder's right-click menu on empty space (Desktop + every folder).
/// Sandboxed, so it only asks the Mark app to create the file via `mark://new?dir=…`.
@objc(FinderSync) final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForContainer else { return nil }
        let menu = NSMenu()
        let item = menu.addItem(withTitle: "New Markdown File", action: #selector(newMarkdownFile(_:)), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        return menu
    }

    @objc func newMarkdownFile(_ sender: AnyObject?) {
        guard let dir = FIFinderSyncController.default().targetedURL() else { return }
        NSWorkspace.shared.open(newFileRequestURL(directory: dir))
    }
}
