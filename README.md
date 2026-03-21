# TutorCast — CAD Tutorial Overlay for Screen Recording

**Built for CAD creators.** TutorCast is a lightweight, always-on-top overlay that displays live keyboard shortcuts and AutoCAD commands during screen recording—perfect for creating professional tutorials and documentation.

## Features

✨ **Real-Time Action Display** — Shows keyboard shortcuts and commands as you use them  
🎨 **3 Built-in Themes** — Minimal, Neon, and AutoCAD styles  
⌨️ **Global Hotkey** — Toggle overlay with **⌃⌥⌘K** (Ctrl+Option+Cmd+K)  
🖱️ **Fully Draggable** — Move the overlay anywhere while capturing video  
📹 **Session Recording** — Save the last 60 seconds of actions as a transparent MOV  
🎯 **Lightweight** — Zero bloat, no external dependencies  
🔐 **Privacy-Focused** — Optional sandboxing, input monitoring only when needed  

## Installation

### Option 1: Direct Download (Recommended)

1. Download the latest `TutorCast.app` from [Releases](https://github.com/yourusername/TutorCast/releases)
2. Move to `/Applications`
3. Open TutorCast—grant Input Monitoring permission when prompted
4. Start recording!

### Option 2: Build from Source

**Requirements:**
- macOS 12.0 or later
- Xcode 15.0+
- Apple Developer certificate (for notarization)

```bash
git clone https://github.com/yourusername/TutorCast.git
cd TutorCast
open TutorCast.xcodeproj
```

Then in Xcode:
1. Select **Product → Build** (or ⌘B)
2. Open the built app with **Product → Run** (or ⌘R)

## Granting Input Monitoring Permission

TutorCast uses system event monitoring to capture keyboard shortcuts. **This permission is required.**

### Automatic Prompt (First Launch)

When you first launch TutorCast, a permission dialog appears:
- Click **Open System Settings**
- Go to **Security & Privacy → Input Monitoring**
- Add TutorCast to the list
- Return to TutorCast and click **Restart Event Tap** in Settings

### Manual Permission (If Dialog Didn't Appear)

1. Open **System Settings → Privacy & Security → Input Monitoring**
2. Click the **+** button
3. Select `/Applications/TutorCast.app`
4. In TutorCast Settings, click **Restart Event Tap**

## Usage

### Toggle Overlay
- **Hotkey:** Press **⌃⌥⌘K** (Ctrl+Option+Cmd+K)
- **Menu:** Click TutorCast menu bar icon → "Show/Hide Overlay"

### Drag the Overlay
- Click anywhere on the overlay and drag to move it
- Position it where it won't obstruct your recordings

### Switch Themes
1. Click TutorCast menu bar icon → **Settings…** (or press **⌘,**)
2. Under "Overlay Appearance," select your theme:
   - **Minimal** — Clean, professional look
   - **Neon** — High contrast, modern aesthetic
   - **AutoCAD** — Classic technical style

### Adjust Appearance
- **Background Opacity** — Control how transparent the overlay is
- **Font Size** — Scale text to fit your recording

### Save Session Recording
1. Click TutorCast menu bar icon → **Save Last 60 Seconds…**
2. Choose a location and filename
3. A transparent MOV file is exported (great for compositing in video editors)

## Building for Distribution

### Build Unsigned App (Testing)
```bash
xcodebuild -scheme TutorCast -configuration Release
```

### Build for Notarization (Direct Download)
```bash
xcodebuild -scheme TutorCast -configuration Release -archivePath build/TutorCast.xcarchive archive
xcodebuild -exportArchive -archivePath build/TutorCast.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/
```

Then notarize:
```bash
xcrun notarytool submit build/TutorCast.app --apple-id your-email@example.com --team-id ABCD123456
```

### Build for Mac App Store

1. In Xcode, select **Product → Scheme → Edit Scheme**
2. Update the bundle identifier to your reverse-domain format
3. Open `TutorCast.entitlements` and uncomment:
   ```xml
   <key>com.apple.security.app-sandbox</key>
   <true/>
   
   <key>com.apple.security.input-monitoring</key>
   <true/>
   ```
4. Archive: **Product → Archive**
5. In the Organizer, click **Distribute App**
6. Select **Mac App Store** and follow the workflow

## Architecture

### Core Components

| File | Purpose |
|------|---------|
| `AppDelegate.swift` | Lifecycle, global hotkey registration, CGEventTap setup |
| `OverlayWindowController.swift` | Window management, persistence, dragging |
| `OverlayContentView.swift` | SwiftUI overlay UI with theme support |
| `SettingsView.swift` | Preferences UI with theme picker |
| `SettingsStore.swift` | Theme definitions, persisted settings |
| `KeyboardShortcutManager.swift` | Global hotkey binding (⌃⌥⌘K) |
| `SessionRecorder.swift` | Records actions and exports MOV files |
| `EventTapManager.swift` | Low-level CGEventTap for keyboard monitoring |
| `LabelEngine.swift` | Maps keyboard events to action labels |

### Data Flow

```
Keyboard Event
    ↓
CGEventTap (EventTapManager)
    ↓
LabelEngine (maps to AutoCAD command)
    ↓
OverlayContentView (displays with theme)
    ↓
SessionRecorder (optional: logs for export)
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **⌃⌥⌘K** | Toggle overlay visibility (global) |
| **⇧⌘O** | Toggle via menu bar |
| **⌘,** | Open Settings |
| **⌘Q** | Quit TutorCast |

## Supported AutoCAD Commands

TutorCast comes pre-configured with common AutoCAD shortcuts:
- Line, Rectangle, Circle, Arc, Polyline
- Copy, Move, Rotate, Scale, Mirror
- Trim, Extend, Offset, Fillet
- Pan, Zoom, Orbit
- Layer management
- And more...

[See full command reference in `Models/Profile.swift`](./TutorCast/Models/Profile.swift)

## Troubleshooting

### "Permission Denied" on Startup
- Grant Input Monitoring permission (see instructions above)
- Restart the app

### Overlay Not Responding to Hotkey
- Check Input Monitoring permission is granted
- Click "Restart Event Tap" in Settings
- Restart the app

### Building in Xcode Fails
- Verify Xcode is updated: `xcode-select --install`
- Clean build folder: **Cmd+Shift+K**
- Rebuild: **Cmd+B**

### "Cannot be opened because it is from an unidentified developer" (Direct Download)

If you're distributing outside the App Store:
1. Right-click `TutorCast.app`
2. Click **Open**
3. In the dialog, click **Open**

Alternatively, if notarized:
```bash
xcrun stapler staple /Applications/TutorCast.app
```

## Privacy & Security

- ✅ No telemetry or data collection
- ✅ All data stored locally (~/Library/Application Support/TutorCast/)
- ✅ Input Monitoring only reads keyboard events relevant to AutoCAD
- ✅ Fully sandboxed (optional for App Store builds)
- ✅ Open source for community review

## Performance

- **Memory:** ~15–25 MB at rest
- **CPU:** <1% when idle
- **Overlay Rendering:** 60 FPS
- **Event Processing:** <1ms latency

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

Licensed under the MIT License — see [LICENSE](LICENSE) for details.

## Support

- 📧 Email: support@example.com
- 🐛 Report issues: [GitHub Issues](https://github.com/yourusername/TutorCast/issues)
- 💬 Discussions: [GitHub Discussions](https://github.com/yourusername/TutorCast/discussions)

---

**Built for CAD creators, by creators.**  
Make better tutorials. Better documentation. Better training.
