# writestuff (Flutter)

The Flutter port of writestuff. `../FEATURES.md` is the parity checklist against
the Rust app in `../src`, which stays until the port matches it.

```sh
flutter run -d macos                      # or windows / linux
flutter test
flutter analyze
WRITESTUFF_CONFIG_DIR=/tmp/ws flutter run -d macos   # isolated recovery data
```

## Layout

- `lib/src/storage/`: atomic file I/O and `session.json` recovery (same path and format as the Rust app)
- `lib/src/model/`: `Document` (text, saved baseline, undo/redo) and `Panes` (split tree)
- `lib/src/app_state.dart`: all behavior, so widgets stay thin and tests drive this directly
- `lib/src/ui/`: sidebar, panes and editor, bottom toolbar, find bar, dialogs, theme tokens

## Notes

- The macOS app sandbox is disabled, because the editor opens and atomically saves arbitrary files and shares the Rust app's config directory.
- Cmd+Q goes through the window close request (see `macos/Runner/AppDelegate.swift`), so unsaved documents are always prompted for.
- The macOS deployment target is 12.0.
