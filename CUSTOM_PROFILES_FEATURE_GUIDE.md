# TutorCast Custom Profiles Feature - Complete Implementation Guide

## Feature Overview

**Custom User-Created Profiles with Short Display Labels** enables users to create personalized action mapping profiles where each keyboard/mouse shortcut displays a concise label (1-3 characters ideal, up to 8 max) on the overlay. Labels are color-coded by action category for enhanced visual communication during screen recordings and tutorials.

---

## Architecture & Data Model

### 1. **ColorCategory Enum** (Profile.swift)

Defines semantic color categories for visual action classification:

```swift
enum ColorCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case `default`, navigation, zoom, selection, edit, destructive, file
}
```

- **default**: Gray/white (neutral actions)
- **navigation** (Orange): Pan, move, orbit operations
- **zoom** (Cyan): Zoom in/out operations
- **selection** (Green): Select, highlight, choose
- **edit** (Blue): Undo, redo, modify operations
- **destructive** (Red): Delete, cut, clear actions
- **file** (Purple): Save, load, export operations

### 2. **ActionTrigger Struct** (Profile.swift)

Represents a specific keyboard/mouse input event:

```swift
struct ActionTrigger: Codable, Identifiable, Hashable {
    var id: UUID
    var eventDescription: String  // e.g., "Middle Drag", "⌘ + Z", "Scroll Up"
}
```

- Sanitized input (max 256 chars)
- Unique ID for identification
- Human-readable event description

### 3. **ActionMapping Struct** (Profile.swift)

Maps a trigger to its overlay display:

```swift
struct ActionMapping: Codable, Identifiable, Hashable {
    var id: UUID
    var trigger: ActionTrigger
    var label: String  // 1-8 chars displayed on overlay
    var colorCategory: ColorCategory
}
```

- Backward compatible with old `action` field
- Auto-sanitizes label to max 8 characters
- Includes color category for semantic rendering

### 4. **Profile Struct** (Profile.swift)

Container for a complete set of action mappings:

```swift
struct Profile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var mappings: [ActionMapping]
    var isCustom: Bool  // false for built-in, true for user-created
}
```

- Built-in profiles (AutoCAD, Photoshop, Default) have `isCustom=false`
- Cannot delete built-in profiles
- Can duplicate or rename custom profiles

---

## Settings Store Management

### **SettingsStore.swift** Enhancements

#### New Properties
- `@Published var currentProfile: Profile?` - Currently active profile
- Profile persistence using encrypted JSON in Application Support folder
- Keychain-stored AES-256-GCM encryption key

#### Key Methods

**Profile Management:**
- `addProfile(named:)` - Create new custom profile with unique name
- `deleteProfile(at:)` - Remove custom profile, auto-switch if active
- `duplicateProfile(_ :)` - Clone profile with new name
- `renameProfile(_ :to:)` - Rename profile with duplicate prevention
- `updateMappings(for:mappings:)` - Persist mapping changes
- `setActiveProfile(_ :)` - Switch active profile and notify observers

**Loading & Persistence:**
- `load()` - Decrypt and load profiles on app launch, seed defaults if first run
- `save()` - Encrypt and persist all profiles
- `updateBuiltInProfiles(_:)` - Ensure built-in profiles always have latest mappings

---

## UI Implementation

### **ProfilesTabView.swift** - Profile Management Interface

**Layout:**
- **Left Sidebar** (240pt): Profile list with selection
- **Right Panel**: Profile editor with mapping table

**Sidebar Features:**
- List of all profiles (built-in with lock icon)
- Profile selection (highlight current, show active checkmark)
- Bottom buttons: + New, − Delete (custom only), Duplicate
- Shows mapping count for each profile

**Editor Features:**
- Profile name display with inline edit (custom only)
- Active profile indicator with activate button
- Mapping table with columns:
  - Event description (read-only)
  - Label preview with color dot
  - Category name
  - Edit/Delete action buttons
- "Add Mapping" button at bottom

**Interactions:**
- Click profile to select
- Double-click name to edit (custom only)
- Delete confirmation dialog
- Edit mapping via modal sheet

### **MappingEditorView.swift** - Mapping Configuration Modal

**Sections:**

1. **Input Event** (read-only):
   - Shows captured event description
   - "Recapture" button to re-listen for input
   - "Listening for input…" indicator during capture

2. **Display Label**:
   - Text field (auto-truncate to 8 chars)
   - Character counter: Green if ≤3, Orange if 4-5, Warning if >5
   - Live preview capsule showing how label renders

3. **Live Preview**:
   - Renders label with adaptive font size
   - Shows actual color category
   - Real-time update as user types

4. **Visual Category**:
   - Picker with color swatches and category names
   - Changes preview in real-time

**Validation:**
- Label cannot be empty
- Max 8 characters
- Warning hint for long labels (>5 chars)
- Save button disabled if invalid

---

## Label Engine (LabelEngine.swift)

### **New Properties**
- `@Published var colorCategory: ColorCategory` - Current label's category

### **Updated Processing Logic**

```swift
func processEvent(_ eventDescription: String) {
    // 1. Normalize event for comparison
    // 2. Find exact match in currentProfile.mappings
    // 3. If found: display mapping.label + colorCategory
    // 4. If not found: display sanitized raw event, default color
    // 5. Auto-clear after 2 seconds
}
```

**Normalization:**
- Case-insensitive comparison
- Trim whitespace
- Regex replace multiple spaces with single space

**Display Sanitization:**
- Remove excessive whitespace
- Limit to 12 chars + ellipsis for very long raw events

---

## Overlay Rendering (OverlayContentView.swift)

### **Adaptive Font Sizing**

| Label Length | Font Size | Weight | Design | Spacing |
|---|---|---|---|---|
| 1-3 chars | 1.8× base | Bold | Default | 0.5pt tracking |
| 4-5 chars | 1.2× base | Semibold | Rounded | Normal |
| >5 chars | 0.9× base | Semibold | Rounded | Normal |

### **Visual Enhancements**

1. **Capsule Background** (short labels only):
   - Subtle gradient with color category
   - 40% opacity colored border
   - Enhanced shadow with category color

2. **Color Mapping**:
   - Uses ColorCategory enum values directly
   - Each category has defined (R, G, B) values

3. **Padding Adjustments**:
   - Short labels: 12pt vertical, 16pt horizontal
   - Medium: 10pt vertical, 14pt horizontal
   - Long: 8pt vertical, 12pt horizontal

4. **Status Dot**:
   - Hidden for very short labels (≤3 chars)
   - Visible for longer labels

---

## Built-in Profiles

### **AutoCAD Profile** (21 curated mappings)

| Event | Label | Category |
|---|---|---|
| Middle Drag | Pn | Navigation (Orange) |
| Scroll Up | Z+ | Zoom (Cyan) |
| Scroll Down | Z- | Zoom (Cyan) |
| Left Click | Sel | Selection (Green) |
| Right Click | Mnu | Default |
| ⌘Z | U | Edit (Blue) |
| ⌘⇧Z | R | Edit (Blue) |
| Delete | Del | Destructive (Red) |
| X | Cut | Destructive (Red) |
| ⌘S | S | File (Purple) |
| ⌘N | New | File (Purple) |
| ... and more |

### **Photoshop Profile** (8 mappings)
- Brush → "Br"
- Eraser → "Er"
- Move → "Mv"
- Select → "Sel"
- Undo/Redo → "U" / "R"
- Pan → "Pn"
- Zoom → "Z+" / "Z-"

### **Default Profile** (4 mappings)
- Left Click → "Clk"
- Right Click → "Mnu"
- Scroll Up → "↑"
- Scroll Down → "↓"

---

## Data Persistence & Migration

### **File Storage**

**Location:** `~/Library/Application Support/TutorCast/profiles.json`

**Format:**
- JSON array of Profile objects
- Encrypted with AES-256-GCM (CryptoKit)
- Encryption key stored in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

### **First Launch Behavior**

1. If `profiles.json` doesn't exist:
   - Create default set: AutoCAD, Photoshop, Default
   - Set AutoCAD as active
   - Persist with encryption

2. On every launch:
   - Load encrypted profiles
   - Update built-in profile mappings (ensure latest)
   - Maintain custom profiles unchanged

### **Backward Compatibility**

- Old ActionMapping format (just `action: String`) auto-migrates to new `trigger` format
- Existing app state preserved on upgrade

---

## Edge Cases & Safety

### **Handled Edge Cases**

1. **Duplicate Trigger Prevention**:
   - Validation during manual edit (future enhancement)
   - UI could warn: "This event is already mapped"

2. **Profile Name Collision**:
   - Auto-append " 2", " 3" etc. via `uniqueProfileName()`
   - Prevents accidental overwrites

3. **Active Profile Deletion**:
   - If deleted profile is active, auto-switch to first available
   - activeProfileID updated in AppStorage

4. **Empty Profile**:
   - Can create profile with zero mappings
   - Falls back to raw event display (no label match)

5. **Long Label Rendering**:
   - Font size scales down to 0.9×
   - Never truncates (full label always visible)
   - Warning hint in editor for >5 chars

6. **Input Sanitization**:
   - All user input sanitized (256 char max for events, 8 for labels)
   - Control characters removed
   - HTML/injection attack prevention

### **Safety Mechanisms**

- **Cannot delete built-in profiles** (UI prevents, code validates)
- **Confirmation dialogs** for destructive actions (delete profile, delete mapping)
- **Inline validation** in mapping editor with error messages
- **Live preview** prevents surprises in overlay rendering
- **Encrypted storage** protects sensitive configuration data

---

## Integration Points

### **KeyMouseMonitor → LabelEngine → OverlayContentView**

```
KeyMouseMonitor detects input
    ↓ publishes raw event description
    ↓
LabelEngine subscribes to $lastEvent
    ↓ looks up in currentProfile.mappings
    ↓ finds mapping & extracts label + colorCategory
    ↓
OverlayContentView observes LabelEngine.$currentLabel & .$colorCategory
    ↓ renders adaptive label with category color
```

### **SettingsStore → ProfilesTabView → MappingEditorView**

```
User opens Settings → Profiles tab
    ↓
ProfilesTabView displays all profiles from SettingsStore.$profiles
    ↓ user clicks Edit on mapping
    ↓
MappingEditorView modal opens
    ↓ user updates label/category
    ↓ clicks Save
    ↓
SettingsStore.updateMappings(for:mappings:) persists changes
    ↓
LabelEngine updates from SettingsStore.$currentProfile observer
    ↓
OverlayContentView reflects new labels on screen
```

---

## Future Enhancements

1. **Input Capture UI**:
   - Full-screen overlay during capture mode
   - Show "Press key or perform mouse action now…"
   - 10-second timeout with visual countdown
   - Automatic event description generation

2. **Menu Bar Integration**:
   - "Active Profile: [Name]" menu item
   - Submenu showing all profiles with checkmark on current
   - Click to switch profiles instantly

3. **Import/Export**:
   - Export profile as JSON to share
   - Import from file to load shared profiles

4. **Profile Templates**:
   - Library of community-created profiles
   - Built-in suggested mappings for various CAD tools

5. **Duplicate Trigger Warnings**:
   - Highlight when same event mapped twice in profile
   - Suggest consolidation

---

## Testing Scenarios

### **Happy Path**

1. Launch app → Auto-load AutoCAD profile
2. Perform "Middle Drag" → Overlay shows "Pn" (orange)
3. Open Settings → Profiles tab
4. Click "New Profile" → Create custom "MyCAD"
5. Click "Add Mapping" → Edit modal opens
6. Manually type event: "Custom Action", label: "CAD"
7. Save → Mapping added to profile
8. Switch active profile to MyCAD
9. Perform "Custom Action" → Overlay shows "CAD"

### **Edge Cases**

1. Delete active profile → Auto-switch to first, no crash
2. Create profile with empty name → Shows error, prevent save
3. Edit label to 20 chars → Auto-truncate to 8
4. Duplicate "AutoCAD" → Creates "AutoCAD copy" with all mappings
5. Rename profile to existing name → Auto-append " 2"
6. Force-quit during save → Encrypted file remains valid on relaunch

---

## Code Quality & Best Practices

### **Implemented Standards**

✓ `@MainActor` for all UI-related state  
✓ `@Published` properties for reactive updates  
✓ Input sanitization (all user data validated)  
✓ Encrypted persistence (AES-256-GCM)  
✓ Backward compatibility (migration logic)  
✓ Error handling (try-catch for decode/encode)  
✓ Type safety (strong typing, no force unwraps where avoidable)  
✓ Documentation (inline comments, clear method names)  
✓ Previews (SwiftUI previews for all view components)  

### **No External Dependencies**

- Pure SwiftUI + Combine
- Native CryptoKit (macOS 10.15+)
- Standard Foundation utilities

---

## Files Created/Modified

| File | Status | Changes |
|---|---|---|
| Models/Profile.swift | ✏️ Modified | New: ColorCategory, ActionTrigger; Enhanced: ActionMapping, Profile |
| Models/SettingsStore.swift | ✏️ Modified | New: profile management methods, currentProfile tracking |
| Models/LabelEngine.swift | ✏️ Modified | New: ColorCategory matching, event normalization |
| OverlayContentView.swift | ✏️ Modified | Adaptive font sizing, color categories, capsule styling |
| SettingsView.swift | ✏️ Modified | Tabbed interface with Profiles tab |
| Views/ProfilesTabView.swift | ✨ New | Complete profile management UI |
| Views/MappingEditorView.swift | ✨ New | Mapping editor modal with live preview |

---

## Summary

The **Custom Profiles** feature provides users with powerful, intuitive control over action mapping while maintaining simplicity through:

- **Short, memorable labels** (1-3 chars ideal) for quick visual scanning
- **Color-coded categories** for semantic meaning at a glance
- **Adaptive typography** that scales with label length
- **Intuitive UI** with sidebar selection and inline editing
- **Secure persistence** using modern encryption standards
- **Built-in profiles** with curated AutoCAD, Photoshop, and generic mappings
- **Full backward compatibility** with existing data

Users can now create custom profiles tailored to their specific workflows, dramatically enhancing the value of TutorCast for CAD tutorials, game recordings, and software demos.
