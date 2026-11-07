# Markdown Quick Editor — Design

## Why

Making a Markdown file today means opening a terminal or an IDE. The user wants to
right-click on the Desktop (or anywhere in Finder), get a new `.md` file, and start
writing immediately in a minimal, good-looking window that shows the formatting live.

## Goals

- Right-click empty space on the Desktop or in any Finder window → **New Markdown File**
  → `Untitled.md` is created in that folder and opens in the editor.
- A very lightweight editor that shows the Markdown styled in real time as you type.
- Vercel-style look: minimal, monochrome, Geist font, follows system light/dark.
- Available in Finder's **Open With** menu for `.md` files (not forced as the default).

## Non-goals

- No preview pane or split view. One pane that styles as you type.
- No toolbar, sidebar, file browser, tabs, settings window, export, or sync.
- No notch integration for now.

## Anti-goals (would count as a failure even if it works)

- Feels heavy: slow launch, Electron/web view, big UI.
- Gets in the way of typing: hides Markdown syntax so the raw text is hard to edit,
  save dialogs, popups.
- Looks generic or busy instead of clean Vercel-style.

## Decided by the user

- Entry point: right-click in Finder/Desktop. (Notch: later, maybe.)
- Normal app (Dock icon, quits when last window closes), not an always-running background app.
- Editor: extremely lightweight, live view of the Markdown as you type.
- Should be one of the "Open With" options for `.md` files.

## Builder's calls (Claude's choices, user can override)

- **Platform:** native macOS app in Swift (AppKit `NSTextView`), no third-party
  dependencies, no web view. Target the installed macOS (26).
- **Live styling:** in place, same text buffer. Headings get larger and bold, `**bold**`
  bold, `*italic*` italic, `` `code` `` and fenced blocks monospace with a subtle
  background, `> quotes` dimmed, list markers and links tinted. The syntax characters
  (`#`, `**`, backticks) stay visible but in a faded gray. Re-style on each edit
  (whole document is fine for typical note sizes).
- **Window:** document-based app (`NSDocument`), thin title bar showing only the
  filename, generous padding, readable column width (~720pt max) centered. Autosave
  in place, no save dialogs.
- **Font:** Geist / Geist Mono bundled in the app (SIL Open Font License); fall back
  to the system font if loading fails.
- **Colors:** pure white / near-black (`#0a0a0a`) background, text near-black /
  near-white, gray (`#888`) for syntax markers. Nothing else.
- **Right-click menu:** a Finder Sync extension adds "New Markdown File" to the
  background (empty-space) context menu of the Desktop and all folders. It creates
  `Untitled.md`, or `Untitled 2.md` etc. if the name is taken, then opens it in the app.
- **App lifecycle (user decided: option b):** normal app with a Dock icon that quits
  when the last window closes. No background process, no login item, no menu-bar icon.
- **Fallback entry point:** launching the app (Dock, Spotlight) with no file creates a
  new `Untitled.md` on the Desktop and opens it. Cmd-N does the same while it's open.
- **Signing:** this Mac has no Apple developer identity. Build with ad-hoc signing.
  The user enables the extension once in System Settings → General → Login Items &
  Extensions. If macOS refuses to load an ad-hoc signed Finder extension, report it
  plainly and rely on launching the app from Spotlight/Dock.
- **Open With:** declare `.md` / `net.daringfireball.markdown` as an editor type with
  handler rank `Alternate`, so it shows in Open With without stealing the default.
- **Install:** a script that builds and copies the app to `/Applications` and launches
  it once so macOS registers the extension.

## Left to the builder

- Project structure and build tooling (Xcode project vs. generated), file layout.
- Exact regex/parsing approach for styling, exact sizes and spacing.
- App icon.
