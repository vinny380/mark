import AppKit
import MarkCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Plain launch (Dock / Spotlight) with nothing to open → new file on the Desktop.
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        newMarkdownFile(nil)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                open(url)
            } else if let dir = directory(fromNewFileRequest: url) {
                create(in: dir)
            }
        }
    }

    /// ⌘K: Markdown files in the current file's folder, or anywhere on the Mac as you type.
    @objc func quickOpen(_ sender: Any?) {
        let docs = NSDocumentController.shared
        let current = (docs.currentDocument ?? docs.documents.first)?.fileURL?.deletingLastPathComponent() ?? desktop
        QuickOpen.shared.show(over: NSApp.keyWindow, folder: current) { [weak self] url in self?.open(url) }
    }

    @objc func makeTextBigger(_ sender: Any?) { Theme.scale = min(2, (Theme.scale * 10 + 1).rounded() / 10) }
    @objc func makeTextSmaller(_ sender: Any?) { Theme.scale = max(0.7, (Theme.scale * 10 - 1).rounded() / 10) }
    @objc func makeTextActualSize(_ sender: Any?) { Theme.scale = 1 }

    @objc func newMarkdownFile(_ sender: Any?) {
        create(in: desktop)
    }

    private var desktop: URL { FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0] }

    private func create(in dir: URL) {
        do {
            open(try createUntitledMarkdown(in: dir))
        } catch {
            // Folder not writable → still give them a file, on the Desktop, and say why in a sheet.
            // (A modal alert here is unreliable: launched in the background via URL, runModal returns .cancel at once.)
            guard dir.standardizedFileURL != desktop.standardizedFileURL,
                  let url = try? createUntitledMarkdown(in: desktop) else { NSApp.presentError(error); return }
            open(url) { window in
                let alert = NSAlert()
                alert.messageText = "Saved to your Desktop instead"
                alert.informativeText = "Couldn’t create a file in \(dir.path).\n\n\(error.localizedDescription)"
                alert.beginSheetModal(for: window)
            }
        }
    }

    private func open(_ url: URL, then: ((NSWindow) -> Void)? = nil) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, error in
            if let error { NSApp.presentError(error) }
            if let window = doc?.windowForSheet { then?(window) }
        }
    }
}

@MainActor func makeMainMenu() -> NSMenu {
    func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        return i
    }
    func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let m = NSMenu(title: title)
        items.forEach(m.addItem)
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = m
        return i
    }
    func finder(_ title: String, _ action: NSTextFinder.Action, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let i = item(title, #selector(NSTextView.performTextFinderAction(_:)), key, mods)
        i.tag = action.rawValue
        return i
    }
    let arrow = { (c: Int) in String(UnicodeScalar(c)!) }
    let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
    recent.submenu = RecentMenu.shared.menu

    let main = NSMenu()
    main.addItem(submenu("Mark", [
        item("About Mark", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
        .separator(),
        item("Hide Mark", #selector(NSApplication.hide(_:)), "h"),
        item("Quit Mark", #selector(NSApplication.terminate(_:)), "q"),
    ]))
    main.addItem(submenu("File", [
        item("New", #selector(AppDelegate.newMarkdownFile(_:)), "n"),
        item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
        recent,
        item("Go to File…", #selector(AppDelegate.quickOpen(_:)), "p"),
        item("Save", #selector(NSDocument.save(_:)), "s"),
        .separator(),
        item("Close", #selector(NSWindow.performClose(_:)), "w"),
        item("Rename…", #selector(NSDocument.rename(_:))),
    ]))
    main.addItem(submenu("Edit", [
        item("Undo", #selector(EditorTextView.undo(_:)), "z"),
        item("Redo", #selector(EditorTextView.redo(_:)), "z", [.command, .shift]),
        .separator(),
        item("Cut", #selector(NSText.cut(_:)), "x"),
        item("Copy", #selector(NSText.copy(_:)), "c"),
        item("Paste", #selector(NSText.paste(_:)), "v"),
        item("Select All", #selector(NSText.selectAll(_:)), "a"),
        .separator(),
        finder("Find…", .showFindInterface, "f"),
        finder("Find and Replace…", .showReplaceInterface, "f", [.command, .option]),
        finder("Find Next", .nextMatch, "g"),
        finder("Find Previous", .previousMatch, "g", [.command, .shift]),
    ]))
    func heading(_ title: String, _ level: Int) -> NSMenuItem {
        let i = item(title, #selector(EditorTextView.setHeadingLevel(_:)), "\(level)", [.command, .option])
        i.tag = level
        return i
    }
    main.addItem(submenu("Format", [
        item("Bold", #selector(EditorTextView.toggleBold(_:)), "b"),
        item("Italic", #selector(EditorTextView.toggleItalic(_:)), "i"),
        item("Strikethrough", #selector(EditorTextView.toggleStrikethrough(_:)), "x", [.command, .shift]),
        item("Inline Code", #selector(EditorTextView.toggleInlineCode(_:)), "e", [.command, .shift]),
        item("Link", #selector(EditorTextView.insertLink(_:)), "k"),
        .separator(),
        heading("Heading 1", 1), heading("Heading 2", 2), heading("Heading 3", 3), heading("Plain Text", 0),
        .separator(),
        item("To-do", #selector(EditorTextView.toggleTodoItem(_:)), "\r"),
        .separator(),
        item("Move Line Up", #selector(EditorTextView.moveLineUp(_:)), arrow(NSUpArrowFunctionKey), .option),
        item("Move Line Down", #selector(EditorTextView.moveLineDown(_:)), arrow(NSDownArrowFunctionKey), .option),
    ]))
    main.addItem(submenu("View", [
        item("Preview", #selector(EditorTextView.togglePreview(_:)), "e"),
        .separator(),
        item("Bigger", #selector(AppDelegate.makeTextBigger(_:)), "+"),
        item("Smaller", #selector(AppDelegate.makeTextSmaller(_:)), "-"),
        item("Actual Size", #selector(AppDelegate.makeTextActualSize(_:)), "0"),
    ]))
    let window = submenu("Window", [item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")])
    main.addItem(window)
    NSApplication.shared.windowsMenu = window.submenu
    return main
}

/// File ▸ Open Recent, filled from the system's recent-documents list each time it opens.
@MainActor final class RecentMenu: NSObject, NSMenuDelegate {
    static let shared = RecentMenu()
    let menu = NSMenu(title: "Open Recent")

    override init() {
        super.init()
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let i = NSMenuItem(title: url.lastPathComponent, action: #selector(open(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = url
            i.toolTip = url.path
            menu.addItem(i)
        }
        if menu.items.isEmpty { menu.addItem(NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: ""))
    }

    @objc private func open(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
}
