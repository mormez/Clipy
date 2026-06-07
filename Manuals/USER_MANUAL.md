# Modern Clipboard — User Manual

**Version 1.0 · macOS 15+ · Apple Silicon**

---

## Table of Contents

1. [Overview](#1-overview)
2. [Requirements & Installation](#2-requirements--installation)
3. [First Launch & Permissions](#3-first-launch--permissions)
4. [The Menu Bar Icon](#4-the-menu-bar-icon)
5. [Clipboard History](#5-clipboard-history)
6. [Snippets](#6-snippets)
7. [Keyboard Shortcuts](#7-keyboard-shortcuts)
8. [Preferences](#8-preferences)
9. [Excluding Apps](#9-excluding-apps)
10. [Automatic Updates](#10-automatic-updates)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Overview

Modern Clipboard is a lightweight menu bar app that keeps a history of everything you copy and lets you paste any previous item in seconds. It also stores reusable text snippets organized in folders — think boilerplate responses, code templates, or frequently used strings — all accessible through a keyboard-driven popup.

**What it does:**

- Silently monitors your clipboard in the background
- Stores up to 50 copied items (text, rich text, images, file paths)
- Provides a fast keyboard-driven popup to browse and paste any history item
- Organizes reusable snippets in named folders
- Excludes sensitive apps (e.g., password managers) from capture
- Lives entirely in the menu bar — no Dock icon, no interruptions

---

## 2. Requirements & Installation

| Requirement | Detail |
|-------------|--------|
| macOS | 15.0 (Sequoia) or later |
| Architecture | Apple Silicon (arm64) |
| App Store | No — distributed independently |
| Sandbox | No |

**To install:** Copy `Modern Clipboard.app` to your `/Applications` folder and double-click to launch.

**To launch at login:** Enable **Preferences → General → Launch Modern Clipboard at login**.

---

## 3. First Launch & Permissions

Modern Clipboard requires **Accessibility permission** to simulate the paste keystroke (⌘V) on your behalf. Without it, you can browse history but pasting will not work.

### Granting Accessibility Permission

1. On first launch, macOS displays a permission prompt — click **Open System Settings**.
2. In **System Settings → Privacy & Security → Accessibility**, find **Modern Clipboard** and toggle it on.
3. You may be asked to enter your password.

If you missed the prompt, open **Preferences** (⌘, from the menu bar), go to the **General** tab, and click **Open System Settings** next to the Accessibility status indicator.

**Status indicators in Preferences:**

| Indicator | Meaning |
|-----------|---------|
| ✓ (green) | Permission granted — paste works |
| ⚠ (orange) | Permission missing — click to open Settings |

---

## 4. The Menu Bar Icon

Modern Clipboard adds a clipboard icon to your menu bar. Clicking it opens a traditional dropdown menu.

### Menu Structure

```
Clipboard History          ← section header
  1. [first item preview]  ⌘1
  2. [second item preview] ⌘2
  …
────────────────────────
  Snippets ▶              ← submenu per folder
────────────────────────
  Clear History…
  Edit Snippets…
  Check for Updates…
  Preferences…            ⌘,
  Quit Modern Clipboard    ⌘Q
```

- Items 1–9 have keyboard shortcuts (⌘1 through ⌘9) when the menu is open.
- Click any history item or snippet to paste it into your frontmost application.
- **Clear History…** asks for confirmation before deleting all items.

> **Tip:** The popup (⌘⇧V) is faster for navigating large histories — the menu is best for quick one-click access to recent items.

---

## 5. Clipboard History

### How Capturing Works

Modern Clipboard polls the clipboard every 0.5 seconds. When it detects new content, it saves a copy.

**Supported content types** (in order of priority):

| Type | How it appears |
|------|----------------|
| Images | "[Image]" label with thumbnail |
| File URLs | Filename (or full path if no filename) |
| Plain text | First 100 characters of content |
| Rich text (RTF) | Plain text extracted from markup |
| HTML | Plain text extracted from markup |

**Deduplication:** Copying the same content twice does not create a duplicate. The existing entry moves to the top of the list instead.

**Empty content:** Blank clipboard entries are silently discarded.

### The History Popup

Press **⌘⇧V** (default; customizable) anywhere to open the history popup.

The popup has two panels:

- **Left — Folder/Group panel:** Groups of items (e.g., "1 – 10", "11 – 20") or a flat list, depending on your display mode setting.
- **Right — Items panel:** The items inside the selected group.

#### Navigating the Popup

**Folder/Group level:**

| Key | Action |
|-----|--------|
| ↓ / ↑ | Move between groups |
| → or ⏎ | Open selected group |
| 1 – 9 | Jump directly to item (flat mode only) |
| Esc | Close popup |

**Item level (inside a group):**

| Key | Action |
|-----|--------|
| ↓ / ↑ | Move between items |
| ⏎ | Paste selected item |
| 1 – 9 | Paste item at that position |
| ← or Esc | Return to group list |

You can also use the mouse: hover to highlight, click to select or paste.

#### History Display Modes

Configure in **Preferences → General → History Menu Style**:

| Mode | Behavior |
|------|---------|
| Always in subfolders | Items always grouped as "1 – 10", "11 – 20", … |
| First 10 flat, older in subfolders | Top 10 shown directly; older items in groups |
| Flat when 10 or fewer | Single flat list if ≤ 10 items; switches to groups above 10 |

#### How Pasting Works

1. Select an item and press ⏎ (or click).
2. The popup closes immediately.
3. The app you were using before the popup is brought to the front.
4. Modern Clipboard sets the clipboard to the selected item.
5. A ⌘V keystroke is sent to paste it.
6. The clipboard monitor pauses briefly (1.5 s) to avoid re-capturing the pasted content.

> **Note:** Steps 4 and 5 require Accessibility permission. If paste does not work, check the permission status in Preferences.

#### Sorting History

In **Preferences → General → Sort Order**, choose:

- **Date Created** — newest copied item is always at the top (default)
- **Last Used** — items you paste most recently float to the top

#### Clearing History

Click **Clear History…** in the menu bar menu. A confirmation dialog appears before anything is deleted.

---

## 6. Snippets

Snippets are reusable pieces of text you save manually. Unlike history items, they persist until you delete them and are organized in named folders.

### Opening the Snippets Popup

Press **⇧⌘S** (default; customizable) anywhere to open the snippets popup.

Navigation is identical to the history popup:

- Left panel shows your snippet folders.
- Right panel shows snippets in the selected folder.
- ↓/↑ to move, → or ⏎ to open a folder, ⏎ to paste a snippet, ← or Esc to go back.

### Managing Snippets — The Editor

Open the snippet editor via **menu bar → Edit Snippets…**

The editor has three columns:

#### Folders (left column)

- **+** — Create a new folder (enter a name in the dialog)
- **−** — Delete the selected folder and all its snippets
- **✏** — Rename the selected folder
- Drag rows to reorder folders

#### Snippets (middle column)

With a folder selected on the left:

- **+** — Add a new snippet (enter title and content in the dialog)
- **−** — Delete the selected snippet
- Drag rows to reorder snippets within the folder

#### Detail Editor (right column)

Click any snippet to edit it:

- **Title** — The name shown in menus and the popup
- **Content** — The text that gets pasted (supports multi-line)
- **Save** — Appears when you have unsaved changes; click to save

> **Tip:** On first launch, Modern Clipboard creates a "My Snippets" folder as a starting point. Rename or delete it freely.

---

## 7. Keyboard Shortcuts

### Global Hotkeys (work system-wide)

| Hotkey | Action |
|--------|--------|
| **⌘⇧V** | Open clipboard history popup |
| **⇧⌘S** | Open snippets popup |

Both hotkeys are customizable in **Preferences → General → Hotkeys**.

### Inside a Popup

| Key | Action |
|-----|--------|
| ↓ / ↑ | Navigate items or groups |
| → | Open selected group / enter item panel |
| ← | Return to group list |
| ⏎ | Paste selected item / open group |
| 1 – 9 | Jump to or paste item at that number |
| Esc | Close popup (or return to group list if in items) |

### Menu Bar

| Hotkey | Action |
|--------|--------|
| ⌘, | Open Preferences |
| ⌘Q | Quit Modern Clipboard |
| ⌘1 – ⌘9 | Paste history item 1–9 (when menu is open) |

### Changing a Hotkey

1. Open **Preferences → General**.
2. Click the hotkey button you want to change (it turns red and shows "Press shortcut…").
3. Press your desired key combination (must include at least one modifier: ⌘, ⌥, ⇧, or ⌃).
4. The new shortcut is registered immediately.
5. Press **Restore Default** to revert to the original hotkey.

> Press Esc while recording to cancel without changing the hotkey.

---

## 8. Preferences

Open Preferences with ⌘, or via the menu bar menu.

### General Tab

#### Permissions

Shows whether Accessibility permission has been granted. Click **Open System Settings** if it hasn't.

#### Clipboard History

| Setting | Options | Default | Effect |
|---------|---------|---------|--------|
| History Menu Style | Three modes (see §5) | Always in subfolders | How items are grouped in popup and menu |
| Max History Items | 5 – 50 | 20 | Maximum items kept; oldest are trimmed automatically |
| Items Panel Width | 200 – 600 px | 400 px | Width of the right panel in the popup |
| Preview Lines | 1 – 3 | 2 | Lines of text shown per item in the popup |
| Sort Order | Date Created / Last Used | Date Created | How history is ordered |

#### Startup

**Launch Modern Clipboard at login** — registers the app with macOS Login Items so it starts automatically when you log in.

#### Hotkeys

Two hotkey recorders — one for the history popup, one for the snippets popup. Click either to record a new shortcut. Click **Restore Default** to go back to ⌘⇧V or ⇧⌘S.

---

### Exclude Apps Tab

Some apps (particularly password managers) place sensitive data on the clipboard. Modern Clipboard can be told to ignore clipboard changes from these apps entirely.

**To add an app:**

1. Go to **Preferences → Exclude Apps**.
2. Click **+** to open a file picker (opens `/Applications` by default).
3. Select the app you want to exclude.

**To auto-exclude common password managers:**

Click **Auto-exclude known password managers**. This immediately adds the following apps (if installed):

- 1Password (v7 and v8)
- Bitwarden
- LastPass
- Dashlane
- KeePassXC
- Strongbox
- NordPass
- RoboForm
- Enpass
- Keeper
- Proton Pass

**To remove an exclusion:** Click the **−** button next to any app in the list.

Each row shows the app icon, display name, and bundle ID so you can easily identify entries.

---

### About Tab

Shows app version, developer info, and contact email. Contains:

- **Check for Updates…** — manually trigger an update check
- **Copyright** — view the open-source MIT license

---

## 9. Excluding Apps

Clipboard monitoring respects the exclusion list on a per-app basis. When a copied item is detected, Modern Clipboard checks which app is currently frontmost. If that app's bundle ID is in the exclusion list, the item is silently skipped — it never enters history and cannot be pasted from Modern Clipboard.

This is most important for:

- Password managers (auto-fill passwords, credit card numbers)
- Banking or sensitive form apps
- Any app where you frequently copy private data

> **How it works technically:** Modern Clipboard checks the frontmost app's bundle ID at capture time, not at paste time. Exclusion only affects recording; if an item was already in history, it remains there.

---

## 10. Automatic Updates

Modern Clipboard uses the **Sparkle** framework for software updates.

- Background checks happen automatically at startup.
- You can trigger a manual check via **menu bar → Check for Updates…** or **Preferences → About → Check for Updates…**
- When an update is available, a standard Sparkle dialog appears with release notes and an option to install.

---

## 11. Troubleshooting

### Paste does nothing / clipboard not updated

**Cause:** Accessibility permission not granted.

**Fix:** Open **Preferences → General** and look for the ⚠ orange warning next to Accessibility. Click **Open System Settings**, find Modern Clipboard in the list, and enable it.

---

### History popup doesn't open on ⌘⇧V

**Possible causes and fixes:**

1. **Permission conflict:** Another app may have registered the same hotkey. Try changing Modern Clipboard's hotkey in **Preferences → Hotkeys**.
2. **App not running:** Check that the clipboard icon is visible in the menu bar.
3. **Hotkey was changed:** Open **Preferences → Hotkeys** to see the current hotkey and press **Restore Default** if needed.

---

### Copied items not appearing in history

**Possible causes:**

1. **App is excluded:** The app you copied from may be on the exclusion list. Check **Preferences → Exclude Apps**.
2. **Duplicate item:** The item already exists in history and moved to the top silently.
3. **Empty content:** Blank or whitespace-only clipboard entries are discarded.
4. **History is full:** If the list is full and you lowered the max items, old items may have been trimmed. Increase **Max History Items** in Preferences.

---

### Snippets not appearing in the popup

Open **Edit Snippets…** and verify your snippets are saved (check that the **Save** button is not showing unsaved changes). Ensure the folder containing your snippets exists and is not empty.

---

### App excluded by mistake

Go to **Preferences → Exclude Apps**, find the app in the list, and click the **−** button next to it.

---

### Images show as "[Image]" instead of a preview

This is expected. The popup shows a small thumbnail (18×18 px) and the "[Image]" label. Full image preview is not supported in the popup — paste the item to see the full image in the target app.

---

### Clearing history to start fresh

Click the menu bar icon, then **Clear History…** and confirm. This is permanent and cannot be undone.

---

## Contact & Support

**Developer:** Mor Mezrich — Myrrh Labs  
**Email:** modern.clipboard@gmail.com  
**GitHub:** https://github.com/mormez/ModernClipboard

Modern Clipboard is based on [Clipy](https://github.com/Clipy/Clipy) (MIT License, Clipy Project 2015–2018).
