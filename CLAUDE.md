# Modern Clipboard — Claude Code Instructions

<!-- Project folder: /Users/mormezrich/Documents/Claude Code Projects/Modern Clipboard/ -->

## Project overview
Modern Swift clipboard manager for macOS 26 / Apple Silicon. Personal rebuild of the original [Clipy](https://github.com/Clipy/Clipy) app (no longer supported on new macOS). User's repo: https://github.com/mormez/ModernClipboard.

## Target environment
- macOS 15+ deployment target, arm64 (Apple Silicon)
- Xcode 26.5, Swift 5.9+
- No App Store / no sandbox

## Key architecture
- Menu bar app (`LSUIElement=YES`, `NSApp.setActivationPolicy(.accessory)`)
- Global hotkey: ⌘⌥V (clipboard popup) via `NSEvent` global monitor; ⇧⌘S (snippets popup)
- Paste: set `NSPasteboard` then simulate ⌘V via `CGEvent` — requires Accessibility permission
- `ClipboardMonitor` pauses 1.5 s after paste to avoid re-capturing our own paste
- Snippets stored in `UserDefaults`, organized in folders (`SnippetManager`)
- SwiftUI for Preferences window and Snippets editor window
- AppKit (`NSStatusItem`, `NSPanel`) for all popups

## Source layout
```
Sources/
  AppDelegate.swift
  MenuBarManager.swift
  ClipboardMonitor.swift
  ClipboardHistory.swift
  ClipboardPopupController.swift   ← clipboard popup + snippets popup (⇧⌘S)
  SnippetsEditorWindowController.swift
  SnippetManager.swift
  SnippetFolder.swift / Snippet.swift
  HotkeyManager.swift
  PasteService.swift
  Preferences.swift / PreferencesWindowController.swift
Manuals/
  USER_MANUAL.md
  QUICK_START.md
  Modern Clipboard User Manual.docx
  Modern Clipboard Quick Start.docx
gen_project.py   ← regenerates Modern Clipboard.xcodeproj when adding/removing source files
build.sh         ← build + auto-relaunch (see below)
```

## Building & testing
Always use `./build.sh` to build. On success it automatically:
1. Kills the running `Modern Clipboard` instance
2. Relaunches the new build from `build/DerivedData/Build/Products/Debug/Modern Clipboard.app`

This means every `./build.sh` produces a running app the user can test immediately — no manual quit/reopen needed.

**Adding new source files:** run `python3 gen_project.py` after adding `.swift` files, then rebuild.

**Accessibility permission:** required for paste simulation. Grant once in System Settings → Privacy & Security → Accessibility.

## Bundle ID
`com.modernclipboard.app` (app binary is named `Modern Clipboard`)
