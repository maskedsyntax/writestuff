# writestuff: feature inventory

This is the complete list of features in the Rust/Iced version (commit `25c1e89`),
written down before porting to Flutter. Tick each item once the Flutter build
matches it. Section 14 lists limitations caused by Iced that Flutter may let us
remove.

---

## 1. App shell and window

- [ ] Native desktop app with no accounts, network access or telemetry.
- [ ] Default window size 1050×740, minimum 560×360.
- [ ] Default UI text size is 13.
- [ ] Window title: `<document name>[ •] — writestuff`. The name is the active pane's document, and ` •` appears when it is unsaved.
- [ ] Closing the window is intercepted and runs the quit flow (§9) instead of exiting immediately.
- [ ] **Command-line arguments:** each path argument is opened as a document at startup (`writestuff notes.md another.txt`).
- [ ] **Single instance per config directory:** an OS file lock on `session.lock` is held for the app's lifetime. A second instance fails with: "Cannot lock the recovery session; writestuff may already be running". The OS releases the lock on exit or crash.
- [ ] `WRITESTUFF_CONFIG_DIR` env var replaces the config directory, for isolated testing.

## 2. Layout (top to bottom)

1. **Toolbar** (chrome background):
   - **File** dropdown menu: `Open…`, `Save`, `Save as…`, `Find and replace…`
   - **Tab strip** (scrolls horizontally, fills the remaining width)
   - `+` New tab (tooltip "New tab · Cmd/Ctrl+T")
   - `◫` Split right (tooltip "Split right · Cmd/Ctrl+D")
   - `⊟` Split down (tooltip "Split down · Cmd/Ctrl+Shift+D")
   - `Preview` (tooltip "Toggle Markdown preview")
   - `⋯` Settings (tooltip "Settings · Cmd/Ctrl+,")
   - Tooltips appear below the control.
2. 1px separator
3. **Settings panel** (inline, when open), then a separator
4. **Find/replace bar** (inline, when open)
5. **Pane grid** (fills the remaining space; the 1px gaps between panes show the line color)
6. **Status bar** (optional), with a separator above it
7. **Notice bar** (when there is a notice)
8. **Modal overlay** for the save-changes prompt (40% black scrim, centered bordered box)

## 3. Keyboard shortcuts

The modifier is Cmd on macOS and Ctrl elsewhere. A shortcut is ignored if Alt is
also held. Shortcuts work while the editor has focus and globally when no other
widget consumed the key.

| Action | Keys |
| --- | --- |
| New document/tab | Cmd/Ctrl+N **or** Cmd/Ctrl+T |
| Open | Cmd/Ctrl+O |
| Save | Cmd/Ctrl+S |
| Save as | Cmd/Ctrl+Shift+S |
| Close active tab/document | Cmd/Ctrl+W |
| Close active pane (keep document) | Cmd/Ctrl+Shift+W |
| Split right (vertical axis) | Cmd/Ctrl+D |
| Split down (horizontal axis) | Cmd/Ctrl+Shift+D |
| Toggle find/replace | Cmd/Ctrl+F |
| Toggle settings | Cmd/Ctrl+, |
| Undo | Cmd/Ctrl+Z |
| Redo | Cmd/Ctrl+Shift+Z (all platforms); Ctrl+Y (**non-macOS only**) |
| Font size +1 | Cmd/Ctrl+`=` or `+` |
| Font size −1 | Cmd/Ctrl+`-` |
| Cut/copy/paste/select all and cursor movement | Platform defaults from the text editor |

## 4. Documents

- [ ] Each document has a numeric ID, an optional file path, the current text, and the **saved baseline** text (what is on disk, or empty for new documents).
- [ ] **Dirty** means the current text differs from the saved baseline. Undoing back to the saved text makes the document clean again.
- [ ] **Name:** the file name from the path, or `Untitled <id>` when there is no path.
- [ ] **Markdown detection:** the extension is `.md` or `.markdown`, case-insensitive. An untitled document is never Markdown.
- [ ] New IDs are `max(existing) + 1` and increase for the whole session.
- [ ] Word count is the number of whitespace-separated tokens. Character count is Unicode scalar values, not bytes.
- [ ] Files must be UTF-8. Anything else shows a read error notice.
- [ ] **Exact text preservation:** CRLF vs LF and the presence or absence of a final newline survive editing and saving byte for byte.

## 5. Tabs

- [ ] There is one tab per open document, in a user-defined order.
- [ ] The **active tab** is the document shown in the active pane.
- [ ] A tab label is the name plus ` •` if dirty. Each tab has its own `×` close button.
- [ ] The active tab is styled with the background fill, a 1px line border, radius 3 and normal text. Inactive tabs are transparent with muted text.
- [ ] **Clicking a tab** shows that document in the active pane. Choosing a document that is already visible elsewhere deliberately mirrors it.
- [ ] **Drag to reorder:** press on a tab, move over another tab, and the dragged tab moves to that position. Releasing the left mouse button anywhere ends the drag.
- [ ] Selecting a tab resets the find position.
- [ ] `+` / Cmd+N / Cmd+T creates a blank `Untitled N` document, appends it to the end of the tab list, shows it in the active pane, and focuses the editor.
- [ ] There is always at least one tab. Closing the last one creates a new blank document.

### Closing a tab (Cmd+W or `×`)

- [ ] If that document is currently being saved, nothing closes and the notice "Wait for this document to finish saving." is shown.
- [ ] If it is dirty, the save-changes modal opens (§9).
- [ ] Otherwise it is removed. Every pane that showed it is updated:
  1. Use the first tab that is **not visible in any other pane**.
  2. If there is none and more than one pane exists, **close that pane**. Never mirror a neighbor.
  3. If it is the only pane, show the first tab.
- [ ] The editor regains focus afterwards.

## 6. Split panes

- [ ] Panes form a tiling layout (binary splits). The **maximum is 8 panes**, and further split requests do nothing.
- [ ] **Split right/down** creates a **new blank document** (new tab) in a new pane next to the active one. The new pane becomes active and gets keyboard focus. The original pane keeps its document.
- [ ] Each pane edits its document independently. Two different documents in two panes never affect each other.
- [ ] The same document can be shown in several panes by selecting its tab. Its content is shared and updates live in every pane.
- [ ] **Click a pane** to make it active (the active pane decides the tab highlight, title, status bar, find target and preview toggle).
- [ ] **Resize** by dragging the separators (5px grab area). On hover or drag, the separator turns the primary color at 2px.
- [ ] **Rearrange** by dragging a pane's header onto another pane or edge.
- [ ] **Pane header** appears **only when more than one pane exists**. It shows `●` (active) or `○`, the document name with ` •` if dirty, and a `×` button (tooltip "Close pane · Cmd/Ctrl+Shift+W"). Active header text is normal and inactive is muted.
- [ ] **Closing a pane** removes the view only. The document stays open as a tab. Focus moves to a sibling pane. Closing the only pane does nothing.
- [ ] Preview mode is stored per pane, and new panes start in edit mode.

## 7. Editor

- [ ] Plain-text editor with **syntax highlighting**: Markdown grammar for `.md` files and plain text otherwise. The highlight theme is Base16 Ocean in dark mode and InspiredGitHub in light mode.
- [ ] Padding is 26 top/bottom and 32 left/right. There is no border, and the background is the theme background.
- [ ] Settings control the font family, size, relative line height and word wrap (word wrap or none).
- [ ] **Undo/redo:** a per-document history of up to 200 text snapshots (the oldest is dropped), one per edit action. Each snapshot also stores the cursor and selection, which undo/redo restore. Any new edit clears the redo stack. Replace All counts as a single undo step. History is **not** persisted across restarts.
- [ ] The editor regains focus after New, Split, Close tab, Close pane, Discard and tab selection.

## 8. Markdown preview

- [ ] The `Preview` button toggles the **active pane** between editing and rendered Markdown.
- [ ] Preview starts hidden in every pane.
- [ ] For a non-Markdown document, the pane shows "Save this document as .md to preview Markdown." with padding 24 and size 14.
- [ ] Rendered Markdown scrolls, with padding 24. Its base text size follows the editor font size setting, and it uses light or dark styling to match the theme.
- [ ] The preview updates live as the text changes, because the Markdown is parsed again after each edit.
- [ ] Supported subset: headings, emphasis, lists, code and so on. There are **no remote images and no embedded HTML**.
- [ ] **Clicking a link does not open a browser.** It shows the notice `Link: <uri>` instead.

## 9. Saving, closing and quitting (content safety)

### Open
- [ ] A native file picker titled "Open text file" opens. Cancelling does nothing.
- [ ] The path is canonicalized. **If that file is already open in a tab, that tab is selected** and no duplicate is created.
- [ ] Otherwise a new tab is created with text equal to the saved baseline, so it starts clean.
- [ ] Files are read off the UI thread.

### Save / Save as
- [ ] Save on a document without a path behaves like Save as. Save as always shows the dialog.
- [ ] A native save dialog titled "Save text file" opens, with the file name pre-filled from the current name. Cancelling does nothing.
- [ ] Only **one save runs at a time**. Further save requests are ignored while one is running.
- [ ] Writing a file that is open in a different tab is refused: "This file is already open in another tab. Save to a different file."
- [ ] **Conflict detection:** when saving back to the document's own path, the file is first compared with the last saved baseline. If the disk content differs: "The file changed on disk. Use Save as to preserve both versions." If the file cannot be read: "Cannot verify original file: … Use Save as."
- [ ] **Atomic write:** write to a temp file in the same directory, copy the existing file's permissions to it, fsync, then rename over the target.
- [ ] Saves run off the UI thread.
- [ ] **Snapshot-exact saved marker:** a finished save sets the baseline to the text that *was written*, so edits made during the save stay dirty.
- [ ] A failed or cancelled save leaves the buffer untouched and shows the error as a notice.

### Save-changes modal (when closing a dirty document)
- [ ] Title: "Save changes to <name>?". Body: "Your unsaved changes will be lost if you discard them." Buttons: **Cancel**, **Discard**, **Save**.
- [ ] While the modal is open, **all other actions are blocked** (shortcuts, edits, new tab and so on). Only Cancel, Discard, Save, save completion, background recovery and dismissing the notice still work.
- [ ] **Save** saves the document. If the save succeeds and the document is clean, it is closed (when closing a tab) or the quit flow continues (when quitting).
- [ ] **Discard** closes the document without saving. It is ignored while a save is in progress.
- [ ] **Cancel** closes the modal and aborts any pending quit. It is ignored while a save is in progress.

### Quit flow (window close)
- [ ] The prompt is shown for each dirty document in tab order, one at a time.
- [ ] When quitting, **Save keeps the document in the tab list** (it is not removed), so it is restored next launch. **Discard** removes it.
- [ ] Once no dirty documents remain, recovery is flushed and the app exits. Nothing else is processed after this starts.
- [ ] If the final recovery write fails, the error is shown and **the quit is aborted**.

## 10. Session recovery (autosave of app state)

- [ ] On every state change (edits, tab changes, settings and so on) a recovery write is **debounced by 700 ms** of inactivity. A newer change cancels the pending one.
- [ ] Writes are **serialized**. If a change arrives during a write, exactly one more write follows.
- [ ] Recovery is written atomically with the same safe-write routine as file saves, off the UI thread.
- [ ] Location: `<config dir>/session.json`
  - macOS: `~/Library/Application Support/writestuff/`
  - Windows: `%APPDATA%\writestuff\config\`
  - Linux: `$XDG_CONFIG_HOME/writestuff/` (usually `~/.config/writestuff/`)
- [ ] **Format** (JSON, keep it compatible so existing users keep their data):
  ```json
  {
    "settings": {
      "appearance": "System" | "Light" | "Dark",
      "font": "Monospace" | "Sans" | "Serif",
      "size": 16.0,
      "line_height": 1.6,
      "wrap": true,
      "status": true
    },
    "documents": [
      { "id": 1, "path": "/abs/path.md" | null, "text": "current text", "saved": "baseline text" }
    ],
    "active": 1 | null
  }
  ```
  Missing settings fields fall back to their defaults.
- [ ] **What is restored:** every document (including unsaved and untitled ones), its unsaved text, its dirty state (text compared with saved), tab order, the active document, and settings.
- [ ] **What is not restored:** the split layout, preview state, and undo history. A single pane opens showing the previously active document.
- [ ] On load, duplicate document IDs are skipped, an invalid `active` ID falls back to the first tab, size is clamped to 10–40 and line height to 1.0–2.4. An empty session starts with `Untitled 1`.
- [ ] **Backup:** before each write, the current valid `session.json` is copied to `session.json.bak`.
- [ ] **Corruption handling:**
  - If `session.json` is damaged on load, `.bak` is tried and the notice "Recovery snapshot was damaged (…); restored the previous backup." is shown.
  - If both are damaged, the app starts empty and shows the notice "Could not restore session: … Damaged snapshots are preserved with a .damaged extension on the next recovery write."
  - When the write after that finds an invalid `session.json`, it saves that file as `session-XXXX.damaged` and **does not overwrite the valid `.bak`**.
- [ ] A failed recovery write shows the notice "Session recovery could not be saved: …".
- [ ] Restored file-backed documents are **not** reloaded from disk automatically. The save-conflict check protects them instead.

## 11. Find and replace

- [ ] Opened with Cmd+F or File → Find and replace…. It is a toggle, and opening it focuses the Find field.
- [ ] Bar contents: `Find` input, `Replace with` input, then **Next**, **Replace**, **All**, and `×` (close).
- [ ] Matching is **literal and case-sensitive** and searches the **active document**.
- [ ] **Next** finds the next match after the previous one, **wraps** to the start, and selects the match in the editor. It is Unicode-safe (correct selection with multi-byte characters such as `猫`).
- [ ] Changing the query resets the search position to the start.
- [ ] No match shows the notice "No matches found."
- [ ] **Replace** replaces the current selection **only if it equals the query exactly**, then finds the next match.
- [ ] **All** replaces every occurrence as one undo step and resets the search position.
- [ ] Enter in Find runs Next. Enter in Replace with runs Replace.
- [ ] An empty query makes every action do nothing.

## 12. Settings

The panel is inline below the toolbar and toggles with `⋯`, Cmd+, or **Done**.

| Setting | Control | Values | Default |
| --- | --- | --- | --- |
| Theme | dropdown | System / Light / Dark | System |
| Font | dropdown | Monospace / Sans / Serif (generic system families) | Monospace |
| Size | slider, label shows `Size  N` | 10–40, step 1 | 16 |
| Line height | slider, label shows `Line height  N.N` | 1.0–2.4, step 0.1 | 1.6 |
| Word wrap | checkbox | on/off | on |
| Status bar | checkbox | on/off | on |

- [ ] Footer: "writestuff. just a place to write stuff." (size 11).
- [ ] Settings apply immediately and are persisted through session recovery.
- [ ] **System theme** follows the OS light/dark mode and updates live when the OS mode changes.

### Status bar (when enabled)
- [ ] Left: `Markdown` or `Plain text`. Right: `N words   N characters` and `Ln L, Col C`.
- [ ] Line and column are 1-based. The column counts **characters**, not bytes. It reflects the active pane's document cursor.
- [ ] Text is muted on the chrome background, with padding 6/16.

### Notice bar
- [ ] A single message line with a **Dismiss** button. A new notice replaces the old one. It is used for errors, link clicks and find misses.

## 13. Visual design tokens

| Token | Light | Dark |
| --- | --- | --- |
| Background | `#faf9f6` | `#1b1c1e` |
| Text | `#303330` | `#d9d9d6` |
| Primary | `#536d60` | `#9eafa4` |
| Muted text | `#737873` | `#999c99` |
| Line / separators | `#e0e1db` | `#343638` |
| Chrome (toolbar, status, pane headers) | `#f0f0eb` | `#202123` |
| Success | `#63836a` | `#63836a` |
| Warning | `#ad8650` | `#ad8650` |
| Danger | `#b76c68` | `#b76c68` |

- [ ] Toolbar controls are text buttons with muted text and radius 3. On hover or press they get a line-colored background and normal text.
- [ ] The File dropdown has a transparent background, no border and muted text.
- [ ] Typical sizes: tab label 12, pane header 11, controls 13, modal title 18.

## 14. Known limitations in the Rust build (candidates to improve in Flutter)

These are listed so they are a deliberate decision, not carried over by accident:

- **No line-number gutter.** Iced has no API for one. It is easy in Flutter and was wanted, along with a toggle.
- **Panes showing the same document share its cursor, selection and scroll position.** Flutter can give each pane its own controller while keeping the text shared.
- Undo history is not persisted. Each snapshot is a full copy of the text, which is fine for notes.
- Split layout and preview state are not restored on relaunch.
- The last 700 ms of typing can be lost if the app crashes.
- Only UTF-8 files are supported.
- Markdown links show a notice instead of opening.
- There are no OS installers, file associations or native app menus.
- Atomic replace changes the file's inode and drops extended attributes and hard links.
- The README says the split buttons are `↔`/`↕`, but the code uses `◫`/`⊟`.

## 15. Behaviors covered by tests (use as acceptance tests)

- Atomic save rejects a conflicting write and preserves exact bytes (CRLF, CJK).
- Undo/redo is independent of the saved baseline: undoing back to the saved text is clean, redo makes it dirty again, and the snapshot round-trip keeps it dirty.
- Editing preserves CRLF and the final newline.
- Session JSON round-trip keeps unsaved text, dirty state, tab order and the active document.
- Each recovery write keeps the previous valid snapshot as `.bak`.
- A damaged session falls back to `.bak`, keeps that backup valid, and writes a `.damaged` file.
- The same document shown in two panes shares edits, and undo works from either pane.
- Closing a dirty document requires an explicit Discard. Other actions are blocked meanwhile, and every pane ends up showing a valid document.
- A save that finishes after newer edits does not mark those edits as saved.
- Unicode find selects the correct text, and Replace replaces only that match.
- Saving during quit keeps the document in the tabs for recovery, after which the app is in the exit state and ignores input.
- Split creates an independent blank document, leaves the original pane untouched, and Close pane keeps the document and returns focus to the original.
- The split and close shortcuts use the platform command modifier, and Cmd+W on a dirty document prompts.
- Closing a tab that was split into its own pane removes the pane instead of mirroring the neighbor.
- Split keeps the original document and selects the new one.

## 16. Additions

- [x] UI follows a sidebar-and-canvas layout. The sidebar replaces the tab strip and has New Document, Open and Settings in its footer. Each pane header has Find, Split right, Split down and Close pane icons, and the find bar opens inline under the active pane's header.
- [x] Panes that show the same document keep independent cursors.
- [x] Preview works for any document, including unsaved ones. New documents are Markdown by default, and the save dialog suggests `<name>.md`.
- [x] Rename: click the title (or `···` → Rename…). For an unsaved document this sets its name, which is stored in the session's optional `title` field. For a saved file it renames the file on disk, keeps the extension when none is typed, and refuses names that already exist. Enter or clicking away commits; Esc cancels.
- [x] Lists: Enter continues bullet, numbered (incremented) and checklist items. Enter on an empty item outdents it, or ends the list at the top level. Tab and Shift+Tab nest and un-nest the selected items. Cmd/Ctrl+Shift+8 and Cmd/Ctrl+Shift+7 toggle bullets and numbering. Bullets display as `•` `◦` `▪` by depth.
- [x] Typing is undone in bursts instead of one character at a time. Tab inserts a tab character outside lists.
- [x] Format bar: Markdown documents in Edit mode have a bar under the editor with Bold, Italic, Strikethrough, Code, Link, Heading (cycles H1 → H2 → H3 → off), Bulleted, Numbered and Checklist. The right side shows "Select text to format" or how many words are selected. Bold, italic, strikethrough and code wrap the selection (or the word at the caret) and unwrap it when it is already formatted. Clicking the bar keeps the editor's focus and selection. Shortcuts: Cmd/Ctrl+B, +I, +Shift+X, +E, +K, and +Shift+9 for checklists. They only apply while the editor has focus.
- [x] Close pane also closes its document and removes it from the sidebar, after the usual unsaved-changes prompt. This replaces the Rust behavior noted in section 15. If another pane shows the same document, only the pane closes. Cancel keeps both.
- [x] Each pane has three view modes: **Edit**, **Side by side** (editor on the left, live preview on the right) and **Preview**. Cmd/Ctrl+P toggles Preview, Cmd/Ctrl+Shift+P toggles Side by side, and both are also in the `···` menu. Swapping panes by drag keeps each pane's mode.
- [x] Fonts: Settings → Font has Monospace, Sans and Serif, plus **Other…**, a searchable list of every installed font family with each name drawn in its own font. The list comes from NSFontManager on macOS, `fc-list` on Linux and the Fonts registry key on Windows. The choice is stored in the session's optional `family` field and overrides the built-in choice. The chip shows the chosen family's name, and picking a built-in choice clears it. The font applies to the editor.
