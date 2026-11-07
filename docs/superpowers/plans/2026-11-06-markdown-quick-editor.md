# Mark — Markdown Quick Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app, "Mark", that creates `Untitled.md` from Finder's right-click menu and edits it in a minimal window that styles Markdown live as you type.

**Architecture:** One Swift package. `MarkCore` (pure Foundation, unit-tested) holds file creation, the `mark://new` URL contract and the Markdown tokenizer. `Mark` (AppKit, NSDocument-based) renders tokens onto an `NSTextView`. `MarkFinder` is a sandboxed Finder Sync extension that only opens `mark://new?dir=<path>`; the unsandboxed app creates the file. `scripts/install.sh` assembles the `.app`/`.appex` bundles by hand, ad-hoc signs, installs to `/Applications`.

**Tech Stack:** Swift 6.4, SwiftPM, AppKit, FinderSync, swift-testing. No third-party code. Geist fonts (OFL) bundled.

**Spec:** `docs/superpowers/specs/2026-11-06-markdown-quick-editor-design.md`

## Global Constraints

- macOS 26 deployment target (`.macOS("26.0")`). No dependencies, no web view.
- Bundle ids: app `com.vinny.mark`, extension `com.vinny.mark.finder`. URL scheme `mark`.
- Normal app: Dock icon, quits after last window closes. No login item, no menu-bar icon.
- `.md` declared as Editor with `LSHandlerRank` = `Alternate` (shows in Open With, never steals default).
- Autosave in place; no save dialogs for new files.
- Colors: background `#ffffff` light / `#0a0a0a` dark; syntax markers `#888888`; text = `labelColor`.
- Fonts: Geist / Geist Mono, fallback to system / monospaced system font.
- Ad-hoc signing only (`codesign -s -`). Extension must have `com.apple.security.app-sandbox`.

## Review Focus

1. Emoji / non-ASCII before markup → ranges must be UTF-16 `NSRange`s or styling lands on the wrong characters (test in Task 2).
2. Half-typed markup (`**open`, unclosed ```` ``` ````) → must not style the rest of the document or crash (Task 2).
3. Markup inside fenced code blocks → shown as code, not as headings/bold (Task 2).
4. Right-click in a folder whose path has spaces/unicode, or that is read-only → file created in the right place, or an alert, never a crash (Task 1 tests + Task 3 alert).
5. `* item` list lines → list marker faded, not treated as italic (Task 2).

---

### Task 1: Package + MarkCore file creation and `mark://` URL contract

**Files:**
- Create: `Package.swift`, `Sources/MarkCore/NewFile.swift`, `Tests/MarkCoreTests/NewFileTests.swift`, `.gitignore` (`.build/`, `build/`)

**Interfaces:**
- Produces:
  - `public func createUntitledMarkdown(in directory: URL) throws -> URL` — writes empty file `Untitled.md`, else `Untitled 2.md`, `Untitled 3.md`… Uses `Data().write(to:options: .withoutOverwriting)` in a loop so it never clobbers. Throws if the directory is missing or unwritable.
  - `public func newFileRequestURL(directory: URL) -> URL` — `mark://new?dir=<path>` via `URLComponents` (`queryItems`).
  - `public func directory(fromNewFileRequest url: URL) -> URL?` — returns the dir only if scheme is `mark`, host `new`, `dir` present, and it is an existing directory.
- Package targets: library `MarkCore`; executable `Mark` (deps: MarkCore); executable `MarkFinder` (deps: MarkCore, linker `unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])`, swift `unsafeFlags(["-application-extension"])`); test target `MarkCoreTests`. Tasks 3/4 fill in `Mark`/`MarkFinder`; this task adds placeholder `main.swift` files so the package builds.

- [ ] **Step 1: Write failing tests** (swift-testing, each in a fresh temp dir)
  - `createsUntitled`: returns `dir/Untitled.md`, file exists, 0 bytes.
  - `incrementsWhenTaken`: pre-create `Untitled.md` with "keep"; returns `Untitled 2.md`; original still contains "keep". Third call → `Untitled 3.md`.
  - `throwsForMissingDirectory`: `#expect(throws: (any Error).self)` for `dir/nope`.
  - `roundTripsPathWithSpaces`: dir named `My Notes ünï` → `directory(fromNewFileRequest: newFileRequestURL(directory: d))?.path == d.path`.
  - `rejectsBadRequests`: `nil` for `https://new?dir=/tmp`, `mark://other?dir=/tmp`, `mark://new`, `mark://new?dir=/does/not/exist`, and a dir pointing at a regular file.
- [ ] **Step 2:** `swift test` → FAIL (symbols not defined).
- [ ] **Step 3:** Implement the three functions in `NewFile.swift`.
- [ ] **Step 4:** `swift test` → all pass.
- [ ] **Step 5:** Commit `feat: MarkCore file creation and mark:// URL contract`.

### Task 2: Markdown tokenizer

**Files:**
- Create: `Sources/MarkCore/MarkdownStyler.swift`, `Tests/MarkCoreTests/MarkdownStylerTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum MarkdownStyle: Equatable, Sendable { case heading(Int), bold, italic, code, codeBlock, quote, link, syntax }
  public struct StyleRun: Equatable, Sendable { public let range: NSRange; public let style: MarkdownStyle }
  public enum MarkdownStyler { public static func runs(in text: String) -> [StyleRun] }
  ```
  Ranges are UTF-16 (`NSString`) ranges. Consumers apply runs in array order, later wins; all `.syntax` runs come last.
- Approach: line-based pass for fences/headings/quotes/lists/hr, then `NSRegularExpression` for inline (`**x**`/`__x__`, `*x*`/`_x_`, `` `x` ``, `[t](u)`) only on lines outside fenced blocks. Delimiters must not span lines.

- [ ] **Step 1: Write failing tests** — each asserts `runs(in:)` contains (or not) the listed `StyleRun(range: NSRange(location:length:), style:)`:
  - `"# Hi"` → `(0,4,.heading(1))`, `(0,2,.syntax)`. `"### H"` → `(0,5,.heading(3))`. `"#nospace"` → no heading.
  - `"a **b** c"` → `(2,5,.bold)`, `(2,2,.syntax)`, `(5,2,.syntax)`.
  - `"x *i* y"` → `(2,3,.italic)`, `(2,1,.syntax)`, `(4,1,.syntax)`.
  - `"* item"` → `(0,1,.syntax)`, no `.italic`. `"1. one"` → `(0,2,.syntax)`.
  - `` "`c`" `` → `(0,3,.code)`, `(0,1,.syntax)`, `(2,1,.syntax)`.
  - `"[a](http://x)"` → `(1,1,.link)`, `(0,1,.syntax)`, `(2,11,.syntax)`.
  - `"> q"` → `(0,3,.quote)`, `(0,1,.syntax)`.
  - `"```\n# x **y**\n```"` (length 17) → `(0,17,.codeBlock)`, no `.heading`, no `.bold`.
  - Unclosed fence `"```\nabc"` → `(0,7,.codeBlock)` and no crash.
  - `"**open"` and `"**a\nb**"` → no `.bold`.
  - `"😀 **b**"` → `(3,5,.bold)`.
  - Last run(s) in array for `"# **a**"` are all `.syntax`.
- [ ] **Step 2:** `swift test` → FAIL.
- [ ] **Step 3:** Implement `MarkdownStyler.runs(in:)`.
- [ ] **Step 4:** `swift test` → all pass.
- [ ] **Step 5:** Commit `feat: Markdown tokenizer`.

### Task 3: The Mark app (editor window, theme, lifecycle, bundling)

**Files:**
- Create: `Sources/Mark/main.swift`, `AppDelegate.swift`, `MarkdownDocument.swift`, `EditorTextView.swift`, `Theme.swift`
- Create: `Resources/Info.plist`, `Resources/Fonts/` (Geist + Geist Mono `.otf` + `OFL.txt` from github.com/vercel/geist-font), `scripts/install.sh`

**Interfaces:**
- Consumes: `createUntitledMarkdown(in:)`, `directory(fromNewFileRequest:)`, `MarkdownStyler.runs(in:)`, `StyleRun`, `MarkdownStyle`.
- Produces: `Mark.app` at `build/Mark.app` via `scripts/install.sh --build-only`; `scripts/install.sh` (no flag) also copies to `/Applications/Mark.app` and runs `lsregister -f`.
- `Theme.apply(_ runs: [StyleRun], to storage: NSTextStorage)`; `Theme.background: NSColor` (dynamic light/dark); `Theme.typingAttributes`.
- `@objc(MarkdownDocument) final class MarkdownDocument: NSDocument` — UTF-8 `read(from:ofType:)` / `data(ofType:)`, `autosavesInPlace = true`, builds its window in `makeWindowControllers()`.
- `AppDelegate`:
  - `application(_:open urls:)`: `mark://` → `directory(fromNewFileRequest:)` → `createUntitledMarkdown(in:)` → open; file URLs → `NSDocumentController.shared.openDocument(withContentsOf:display:)`. Creation failure → `NSAlert` with the folder path, no crash.
  - `applicationOpenUntitledFile(_:)` → create on `~/Desktop`, open, return `true` (covers plain launch + Dock click with no windows).
  - `applicationShouldTerminateAfterLastWindowClosed` → `true`.
  - File ▸ New (⌘N) → `newMarkdownFile(_:)` (Desktop). Programmatic main menu: App (About, Hide, Quit), File (New, Open…, Close, Rename…), Edit (Undo, Redo, Cut, Copy, Paste, Select All), Window (Minimize).

Values (from spec / builder's call):
- Body Geist 15pt, line-height multiple 1.5; headings SemiBold 28/22/18/16/15/15; Geist Mono 13.5 for code; code/codeBlock background `#f5f5f5` light / `#171717` dark; quote `secondaryLabelColor`; link underlined; syntax `#888888`.
- Window 760×640 default, min 420×300, `.fullSizeContentView`, transparent titlebar, background `Theme.background`. Text column max 720pt centered: `EditorTextView.setFrameSize` sets `textContainerInset.width = max(48, (width - 720) / 2)`, height inset 56.
- Text view: plain text, undo on, smart quotes/dashes/replacement/spell-correction off. Restyle whole storage on every `textDidChange` (`// ponytail: full restyle per keystroke; incremental by paragraph if >200KB files feel slow`).
- Info.plist: `CFBundleIdentifier com.vinny.mark`, `CFBundleName Mark`, `LSMinimumSystemVersion 26.0`, `ATSApplicationFontsPath Fonts`, `CFBundleURLTypes` scheme `mark`, `CFBundleDocumentTypes` (`net.daringfireball.markdown`, role Editor, rank Alternate, `NSDocumentClass MarkdownDocument`), `UTImportedTypeDeclarations` for `net.daringfireball.markdown` (extensions `md`, `markdown`, conforms to `public.plain-text`).
- install.sh: `swift build -c release`, assemble `build/Mark.app/Contents/{MacOS,Resources,Info.plist}`, copy fonts, (Task 4 adds PlugIns), `codesign --force -s - build/Mark.app`. `set -euo pipefail`.

- [ ] **Step 1:** Download Geist fonts into a fresh temp dir; copy only `Geist-{Regular,Medium,SemiBold,Bold}.otf`, `GeistMono-Regular.otf`, `OFL.txt` into `Resources/Fonts/`. Confirm PostScript names with `mdls -name com_apple_ats_name_postscript` or `fc-scan`; use those exact names in `Theme`.
- [ ] **Step 2:** Implement the five Swift files, `Info.plist`, `install.sh`.
- [ ] **Step 3:** `scripts/install.sh --build-only` → exits 0, `codesign -v build/Mark.app` passes.
- [ ] **Step 4:** `open -a build/Mark.app <tmp>/sample.md` with headings, bold, code block, list, quote, link → screenshot to `.context/editor-light.png`; check styling matches values above. Repeat in dark mode → `.context/editor-dark.png`.
- [ ] **Step 5:** `open "mark://new?dir=<tmpdir with spaces>"` → `Untitled.md` appears there and opens. Run twice → `Untitled 2.md`. Type, close window → content saved, app quits.
- [ ] **Step 6:** `swift test` still passes. Commit `feat: Mark editor app`.

### Task 4: Finder Sync extension + install

**Files:**
- Create: `Sources/MarkFinder/FinderSync.swift` (replaces placeholder `main.swift`; keep an empty `main.swift` if SwiftPM requires one), `Resources/MarkFinder-Info.plist`, `Resources/MarkFinder.entitlements`
- Modify: `scripts/install.sh`

**Interfaces:**
- Consumes: `newFileRequestURL(directory:)`.
- `@objc(FinderSync) final class FinderSync: FIFinderSync` — `init` sets `FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]`; `menu(for: .contextualMenuForContainer)` returns one item "New Markdown File" (SF Symbol `doc.text`); action opens `newFileRequestURL(directory: targetedURL)` with `NSWorkspace.shared.open`.
- Info.plist: `CFBundleIdentifier com.vinny.mark.finder`, `CFBundlePackageType XPC!`, `NSExtension` = { `NSExtensionPointIdentifier com.apple.FinderSync`, `NSExtensionPrincipalClass FinderSync` }, `LSMinimumSystemVersion 26.0`.
- Entitlements: `com.apple.security.app-sandbox` = true.
- install.sh additions: assemble `build/Mark.app/Contents/PlugIns/MarkFinder.appex/Contents/{MacOS/MarkFinder,Info.plist}`; sign appex first with `--entitlements`, then the app. Install path: copy to `/Applications`, `lsregister -f`, `pluginkit -a <appex>`, `pluginkit -e use -i com.vinny.mark.finder`, `killall Finder`.

- [ ] **Step 1:** Implement extension, plist, entitlements, install.sh changes.
- [ ] **Step 2:** `scripts/install.sh` → exits 0; `pluginkit -m -i com.vinny.mark.finder` lists it with `+` (enabled).
- [ ] **Step 3:** Right-click empty space in a Finder window and on the Desktop → "New Markdown File" present → creates and opens `Untitled.md`. Screenshot `.context/finder-menu.png`. If the extension won't load ad-hoc signed, record the exact `pluginkit`/Console error and stop; Spotlight/Dock launch remains the entry point.
- [ ] **Step 4:** In Finder, right-click any `.md` → Open With lists Mark, and the default app is unchanged.
- [ ] **Step 5:** Commit `feat: Finder right-click New Markdown File`.
