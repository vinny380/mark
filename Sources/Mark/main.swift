import AppKit

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.mainMenu = makeMainMenu()
    withExtendedLifetime(delegate) { NSApplication.shared.run() }
}
