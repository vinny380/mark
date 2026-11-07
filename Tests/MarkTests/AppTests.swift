import AppKit
import Testing
@testable import Mark

@Test func dynamicColorsResolveOffMainThread() async {
    let colors = await [Theme.background, Theme.codeBackground]
    await Task.detached {
        for c in colors { _ = c.cgColor } // AppKit may resolve dynamic colors off main; must not trap
    }.value
}

@MainActor @Test func fileMenuHasSave() {
    let file = makeMainMenu().item(withTitle: "File")!.submenu!
    let save = file.items.first { $0.action == #selector(NSDocument.save(_:)) }
    #expect(save?.keyEquivalent == "s")
}
