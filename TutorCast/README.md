# TutorCast

> Floating AutoCAD shortcut overlay for screen recording — macOS 14+

A lightweight menu-bar app that renders a transparent, always-on-top HUD
showing real-time keyboard shortcuts while you record AutoCAD tutorials.

---

## Project Structure (7 files)

```
TutorCast/
├── TutorCastApp.swift            @main entry, MenuBarExtra, Settings scene
├── AppDelegate.swift             Lifecycle, activation policy, EventTap wiring
├── OverlayWindowController.swift NSWindow factory + position persistence
├── OverlayContentView.swift      SwiftUI HUD pill (the visible overlay)
├── EventTapManager.swift         CGEventTap wrapper + permission docs
├── SettingsView.swift            Preferences UI + permission shortcuts
├── TutorCast.entitlements        Hardened Runtime (App Store notes inside)
└── Info.plist                    NSInputMonitoringUsageDescription + LSUIElement
```

---

## Xcode Setup (one-time)

### 1. Create the project

1. Xcode → **File › New › Project**
2. Choose **macOS → App**
3. Product Name: `TutorCast`
4. Interface: **SwiftUI**, Language: **Swift**
5. Uncheck *Include Tests* (optional)

### 2. Replace generated files

Delete the scaffolded `.swift` files Xcode creates and add all `.swift` files
from this repo into the `TutorCast/` group.

### 3. Project settings

| Setting | Value |
|---|---|
| Deployment Target | **macOS 14.0** |
| Swift Language Version | **Swift 6** |
| Bundle Identifier | `com.<yourteam>.TutorCast` |
| Signing Team | Your Apple Developer team |

### 4. Info.plist — Custom Keys

In Xcode's **Info** tab (or directly in `Info.plist`) confirm these keys exist:

| Key | Value |
|---|---|
| `NSInputMonitoringUsageDescription` | *(privacy string — see Info.plist)* |
| `NSAccessibilityUsageDescription` | *(privacy string)* |
| `LSUIElement` | `YES` |
| `LSMinimumSystemVersion` | `14.0` |

### 5. Entitlements

Set the **Code Signing Entitlements** build setting to:
```
TutorCast/TutorCast.entitlements
```

### 6. Build & Run

`Cmd+R` — the app appears in the menu bar (keyboard icon).
A "TutorCast Ready" pill floats on screen.

---

## Permissions (first launch)

TutorCast will **not** crash if permissions are missing — it just prints a
console warning and skips the tap. Grant permissions before expecting
keyboard detection to work.

### Input Monitoring (required)

```
System Settings → Privacy & Security → Input Monitoring → TutorCast ✓
```

Then click **"Restart Event Tap"** in TutorCast Settings, or relaunch.

### Accessibility (sometimes required)

```
System Settings → Privacy & Security → Accessibility → TutorCast ✓
```

Both shortcuts are in **TutorCast → Settings… → Permissions**.

---

## Architecture

### CGEventTap vs NSEvent global monitors

| | `CGEventTap` | `NSEvent` global monitor |
|---|---|---|
| Layer | Quartz event stream | AppKit / NSApplication |
| Latency | Sub-millisecond | Coalesced, higher latency |
| Modify events | ✅ (active tap) | ❌ |
| Reliability | ✅ All events | ⚠️ May miss events |
| Permission | Input Monitoring | Input Monitoring |

TutorCast uses a **passive** (`listenOnly`) `CGEventTap` at the
**session level** — lowest privilege required, maximum reliability.

### Overlay window

```
OverlayWindow (NSWindow)
  └─ DraggableHostingView<OverlayContentView> (NSHostingView subclass)
       └─ OverlayContentView (SwiftUI)
```

- `styleMask = [.borderless]` — no chrome
- `backgroundColor = .clear`, `isOpaque = false` — fully transparent shell
- `level = .floating` — above all normal windows
- `canBecomeKey = false` — never steals keyboard focus from AutoCAD
- `isMovableByWindowBackground = true` + `mouseDownCanMoveWindow = true`
  in hosting view → drag anywhere on the pill

### Data flow (current → future)

```
CGEventTap → EventTapManager.onKeyDown →
  AppDelegate → [ShortcutLookupTable] → OverlayContentView
```

The lookup table (AutoCAD keycode → command name) is the next file to add.
Wire it as an `ObservableObject` injected via `.environmentObject()`.

---

## Extending

### Add AutoCAD shortcut detection

```swift
// In AppDelegate.applicationDidFinishLaunching:
EventTapManager.shared.onKeyDown = { keyCode, flags in
    if let command = AutoCADShortcuts.lookup(keyCode: keyCode, modifiers: flags) {
        overlayModel.currentCommand = command
    }
}
```

### Resize overlay dynamically

```swift
overlayController.resize(to: NSSize(width: 400, height: 72))
```

### Mouse event tap (future)

Add to the `mask` in `EventTapManager.start()`:
```swift
let mask: CGEventMask =
    (1 << CGEventType.keyDown.rawValue) |
    (1 << CGEventType.leftMouseDown.rawValue) |
    (1 << CGEventType.scrollWheel.rawValue)
```
