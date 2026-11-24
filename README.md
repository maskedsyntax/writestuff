# writestuff

just a place to write stuff.

A small native Rust/Iced writing app for plain text and Markdown. Tabs, resizable
split panes, find and replace, syntax highlighting, optional Markdown preview,
light/dark/system themes, and local recovery. No accounts or network services.

## Build and run

Install a current stable Rust toolchain, then:

```sh
cargo run --release
cargo run --release -- notes.md another.txt
```

On macOS install the Xcode command-line tools. Windows needs the MSVC Rust
toolchain and Visual Studio C++ build tools. Linux needs a working Wayland or X11
desktop, Vulkan/OpenGL graphics drivers, and an XDG desktop portal for native file
dialogs (for example `xdg-desktop-portal-gtk`). Iced can fall back to software
rendering. Build output is `target/release/writestuff` (`writestuff.exe` on Windows).

```sh
cargo fmt --check
cargo check
cargo clippy --all-targets -- -D warnings
cargo test
```

## Controls

Use **Cmd** on macOS and **Ctrl** on Windows/Linux.

| Action | Shortcut |
| --- | --- |
| New document/tab | Cmd/Ctrl+N or T |
| Open | Cmd/Ctrl+O |
| Save / Save as | Cmd/Ctrl+S / Shift+S |
| Close tab | Cmd/Ctrl+W |
| Split right / down | Cmd/Ctrl+D / Cmd/Ctrl+Shift+D |
| Close pane (keep document) | Cmd/Ctrl+Shift+W |
| Find and replace | Cmd/Ctrl+F |
| Undo | Cmd/Ctrl+Z |
| Redo | Cmd+Shift+Z; Ctrl+Y or Ctrl+Shift+Z |
| Increase/decrease font | Cmd/Ctrl+Plus / Minus |
| Settings | Cmd/Ctrl+, or `⋯` |
| Cut/copy/paste/select all | Standard platform shortcuts |

Drag a tab by its name to reorder it. Click a pane, then select a tab to show
that document there. `↔` splits side by side; `↕` splits above/below. New panes
start with a separate blank document and receive keyboard focus. Selecting an
already-open tab in a pane deliberately shows that same document there. Drag separators to
resize and pane headers to rearrange; a pane's `×` removes that view without
closing its document. Closing a tab uses an available hidden tab or removes its
empty pane, rather than mirroring a neighboring document. At most eight panes can
be open.

The **File** menu contains Open, Save, Save as, and Find and replace.

**Preview** toggles the active pane between editing and rendered Markdown for
`.md` and `.markdown` files. It starts hidden. Find is literal and case-sensitive;
**Next** wraps around. **Replace** replaces the selected match and finds the next;
**All** replaces every match. Press Enter in Find to select the next match.

Settings offer generic system monospace, sans-serif and serif families, size,
line height, wrapping, theme, and status-bar visibility.

## Content safety and recovery

A dot marks an unsaved document. Closing a changed document or the window asks
you to save, discard, or cancel. Failed/cancelled saves keep your buffer intact.
Saving runs off the UI thread, uses a synced temporary file followed by atomic
replacement, and preserves existing permissions. A save only marks its exact
snapshot as saved, so edits made while saving remain dirty. Existing file changes
are checked against the last saved contents; a conflict requires Save as.

Documents, unsaved text, tab order, active document and preferences are recovered
from `session.json` in the platform configuration directory:

- macOS: `~/Library/Application Support/writestuff/`
- Windows: `%APPDATA%\writestuff\config\`
- Linux: `$XDG_CONFIG_HOME/writestuff/` (usually `~/.config/writestuff/`)

Recovery writes are serialized and occur after 700 ms of inactivity. The previous
snapshot is retained as `session.json.bak`. Recovery is also flushed on normal
exit. Only one instance may use a configuration directory at a time; the OS
releases the session lock on exit or crash. For isolated testing, set
`WRITESTUFF_CONFIG_DIR` to a temporary directory. Recovery files contain your
plain text and are never uploaded.

## Known limitations

- **Line numbers:** Iced 0.14's built-in text editor has no line-number gutter API.
  A synchronized gutter and its toggle are unavailable. Cursor line/column is
  shown in the optional status bar.
- Views of the same document share its cursor, selection and scrolling state,
  as well as its content. Independent cursors would require a custom editor.
- Undo/redo retains 200 text snapshots per document, one per edit action. History
  is not persisted; undo restores its cursor. This is intended for ordinary notes.
- Recovery restores document snapshots, not split geometry or preview state.
  Restored saved files are not automatically reloaded from disk; save-conflict
  checks protect against overwriting external changes. The last 700 ms may be
  unavailable after an abrupt crash. A damaged recovery file is reported and its backup is tried automatically;
  damaged input is preserved separately on the next recovery write.
- Files must be UTF-8. Binary/legacy-encoded files report an error. Existing line
  endings and final-newline presence are preserved by the built-in editor.
- Markdown preview uses Iced's supported Markdown subset, without remote images
  or embedded HTML. Clicking a link displays its target locally.
- External-change checks are best effort, not a filesystem transaction with other
  programs. Atomic replacement changes inode identity and does not preserve
  extended attributes or hard links. Avoid concurrently writing a file elsewhere.
- This is a Cargo executable; OS installer bundles, file associations and native
  application menus are not included. Open and Save use native file dialogs.
- Verified with Rust 1.99.1 on macOS: compilation, linting, unit tests and a native
  visual smoke test in an isolated temporary app bundle. Checked independent split
  editing, both split shortcuts, and the close-tab unsaved-changes prompt.
  Windows/Linux builds and interactive behavior have not been tested here.

The current macOS dependency graph emits a future-compatibility warning for
upstream `block 0.1.6`; application code passes Clippy with warnings denied.
