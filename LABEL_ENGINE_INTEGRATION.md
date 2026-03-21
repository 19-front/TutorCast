# TutorCast Label Engine Integration Guide

## Overview

The Label Engine transforms raw keyboard and mouse events into semantic, application-specific labels based on the active profile. For example, "Middle Drag" becomes "PAN" in the AutoCAD profile and displays in orange.

## Architecture

### Components

1. **LabelEngine.swift** (NEW)
   - Central event processor
   - Watches `KeyMouseMonitor` for raw events
   - Matches events against active profile's action mappings
   - Updates `@Published` properties for UI binding
   - Auto-clears labels after 1.5 seconds
   - Ensures AutoCAD is default profile on first launch

2. **Profile.swift** (EXISTING - Enhanced)
   - `ActionMapping`: Maps raw actions to semantic labels
   - `Profile`: Contains name and array of mappings
   - `BuiltInProfiles`: Seeded with AutoCAD, Photoshop, Default

3. **SettingsStore.swift** (EXISTING - Enhanced)
   - Added `static let shared = SettingsStore()` singleton
   - Manages profile persistence and selection
   - `activeProfile()` returns current profile for LabelEngine

4. **OverlayContentView.swift** (EXISTING - Enhanced)
   - Observes `LabelEngine.currentLabel` and `labelColor`
   - Dynamically colors text based on semantic meaning
   - Colors: orange (pan/orbit), cyan (zoom), green (select), red (delete), white (default)

5. **TutorCastApp.swift** (EXISTING - Enhanced)
   - Menu bar profile switcher
   - Shows active profile name
   - Allows instant profile switching
   - Checkmark indicates current profile

6. **AppDelegate.swift** (EXISTING - Enhanced)
   - Initializes `LabelEngine.shared` on app launch
   - Ensures event monitoring begins immediately

7. **LabelEngineTestView.swift** (NEW)
   - Test/preview helper
   - Simulates events with buttons
   - Displays current state
   - Allows profile switching
   - Useful for development and testing

## Data Flow

```
KeyMouseMonitor (raw event)
        ↓
LabelEngine.processEvent()
        ↓
Check active profile's mappings
        ↓
Match found? → @Published currentLabel + labelColor
        ↓
OverlayContentView observes changes
        ↓
Text updates with color (orange for PAN, cyan for ZOOM, etc.)
        ↓
scheduleAutoClear() → clears after 1.5s
```

## Usage Example

### Testing in Previews

```swift
// In any SwiftUI preview:
KeyMouseMonitor.shared.simulate(event: "Middle Drag")
// → Overlay shows "PAN" in orange
```

### Adding Custom Mappings

Extend `BuiltInProfiles` or create profiles in the Settings window:

```swift
ActionMapping(action: "⌘ + Shift + Z", label: "REDO")
```

### Profile Auto-Selection

On first launch, if `activeProfileID` is empty, LabelEngine automatically selects the "AutoCAD" profile.

## Color Semantics

| Color | Meaning | Examples |
|-------|---------|----------|
| Orange | Navigation | PAN, ORBIT |
| Cyan | Zoom operations | ZOOM IN, ZOOM OUT |
| Green | Selection | SELECT, PICK |
| Red | Destructive | DELETE, CUT |
| White | Default/Other | Commands, UI actions |

## Files Modified

1. **Models/LabelEngine.swift** (NEW)
   - 60 lines
   - Main event processor with color logic

2. **Models/SettingsStore.swift** 
   - Added `static let shared`
   - Line 7

3. **OverlayContentView.swift**
   - Added `@StateObject` for LabelEngine
   - Added color mapping logic
   - Changed text color from `.white` to semantic color

4. **TutorCastApp.swift**
   - Added profile switcher menu
   - 20+ new lines in MenuBarContentView

5. **AppDelegate.swift**
   - Added LabelEngine initialization
   - 2 new lines

6. **LabelEngineTestView.swift** (NEW)
   - 100 lines
   - Test helper for development

## Integration Checklist

- ✅ LabelEngine.swift created with event processing
- ✅ AutoCAD default on first launch
- ✅ OverlayContentView updated with semantic colors
- ✅ Menu bar profile switcher implemented
- ✅ SettingsStore singleton added
- ✅ AppDelegate initializes LabelEngine
- ✅ Test view for verification

## Testing Steps

1. Build and run TutorCast
2. Verify AutoCAD is shown in menu bar as active profile
3. Open test view: LabelEngineTestView()
4. Click "Middle Drag" button → Overlay shows "PAN" in orange
5. Click "Scroll Up" button → Overlay shows "ZOOM IN" in cyan
6. Switch to "Photoshop" profile
7. Click "B" button → Overlay shows "BRUSH" in white
8. Verify 1.5s auto-clear works

## Future Enhancements

1. **Compound Actions**: Support modifier combinations
   - E.g., Shift + Middle Drag = "ORBIT"
   - Implementation: Enhanced action string matching

2. **Custom Color Themes**: Profile-specific label colors
   - Add `labelColors: [String: String]` to Profile

3. **Analytics**: Track which actions are used most
   - Log to local database for user insights

4. **Voice Output**: Optional audio feedback
   - Speak label on action (accessibility feature)

5. **Persistence**: Remember last used profile
   - Auto-restore on app relaunch

## Dependencies

- SwiftUI (iOS/macOS)
- Combine (for @Published)
- Foundation (for UUID, Date)
- AppKit (for NSApplicationDelegate)

All standard macOS frameworks — no external dependencies.
