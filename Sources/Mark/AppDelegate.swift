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
    let find = item("Find…", #selector(NSTextView.performTextFinderAction(_:)), "f")
    find.tag = NSTextFinder.Action.showFindInterface.rawValue

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
        item("Quick Open…", #selector(AppDelegate.quickOpen(_:)), "k"),
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
        find,
    ]))
    main.addItem(submenu("View", [item("Preview", #selector(EditorTextView.togglePreview(_:)), "e")]))
    let window = submenu("Window", [item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")])
    main.addItem(window)
    NSApplication.shared.windowsMenu = window.submenu
    return main
}
