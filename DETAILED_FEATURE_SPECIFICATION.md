# DETAILED FEATURE SPECIFICATION: Custom User Profiles with Short Display Labels

## Executive Summary

This document specifies the complete design and implementation of **custom user-created profiles** for the TutorCast app, enabling users to create personalized shortcuts mapping where each action displays a concise 1-8 character label on the overlay, color-coded by action type for semantic meaning.

**Target:** Professional CAD/Software tutorial creators recording on macOS 14+  
**Tech Stack:** SwiftUI, Combine, CryptoKit (no external dependencies)  
**Scope:** Full end-to-end feature from data model to UI to persistence

---

# PART 1: REQUIREMENTS & USE CASES

## User Stories

### US-01: Create Custom Profile
**As a** tutorial creator recording AutoCAD content,  
**I want to** create a custom profile optimized for my teaching style,  
**So that** I can have shortcuts display with my preferred labels.

**Acceptance Criteria:**
- User can click "+ New Profile" in settings
- Name field accepts 1-128 characters (sanitized)
- New profile starts with zero mappings
- New profile appears in profile list immediately
- User can edit name by double-clicking (custom profiles only)

### US-02: Edit Action Mapping
**As a** profile creator,  
**I want to** define what label appears when I perform an action,  
**So that** viewers understand what I'm doing in real-time.

**Acceptance Criteria:**
- Click "Edit" on any mapping opens modal
- Modal shows: Event description (read-only), Label field, Category picker
- Label field: max 8 chars, auto-truncates, live character counter
- Category picker: 7 semantic options with color preview
- Live preview capsule shows exactly how label will render
- Save validates: label not empty, ≤8 chars
- Mapping updates immediately in table

### US-03: Short Labels Pop on Overlay
**As a** viewer watching a tutorial,  
**I want to** instantly recognize what action is being performed,  
**So that** I don't miss important steps.

**Acceptance Criteria:**
- 1-3 character labels: very large (1.8× base), bold, capsule background
- 4-5 character labels: medium (1.2× base), semibold
- 6-8 character labels: smaller (0.9× base), semibold
- Short labels get colored capsule background matching category
- Font adapts smoothly (no jarring size changes)
- Colors match category consistently (orange = nav, cyan = zoom, etc.)

### US-04: Switch Active Profile
**As a** content creator,  
**I want to** quickly switch between profiles (e.g., AutoCAD vs Blender vs generic),  
**So that** I can record different software tutorials with appropriate labels.

**Acceptance Criteria:**
- Each profile shows "Active" checkmark or "Activate" button
- Click "Activate" on any profile switches immediately
- Active profile persists across app restarts
- LabelEngine uses new profile for matching events
- Overlay labels update to reflect new profile immediately

### US-05: Protect Built-in Profiles
**As a** TutorCast developer,  
**I want to** ensure built-in profiles aren't accidentally deleted,  
**So that** users always have working defaults.

**Acceptance Criteria:**
- Delete button disabled for built-in profiles (grayed out)
- Built-in profiles show lock icon
- Cannot rename built-in profiles via UI
- Built-in mappings auto-update on each app launch
- User can duplicate built-in profiles as starting point

### US-06: Color-Coded Actions
**As a** tutorial viewer,  
**I want to** quickly distinguish types of actions (navigation vs edit vs delete),  
**So that** I understand the workflow without reading labels.

**Acceptance Criteria:**
- Navigation (Pan, Move, Orbit) = Orange
- Zoom operations = Cyan
- Selection operations = Green
- Edit operations (Undo, Redo, Modify) = Blue
- Destructive operations (Delete, Cut) = Red
- File operations (Save, Load) = Purple
- Default/Neutral = White/Gray
- Each category has consistent, readable RGB values

---

# PART 2: DATA MODEL SPECIFICATION

## ColorCategory Enum

```swift
public enum ColorCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case `default` = "default"
    case navigation = "navigation"   // Pan, move, orbit — Orange (1.0, 0.6, 0.0)
    case zoom = "zoom"               // Zoom in/out — Cyan (0.0, 1.0, 1.0)
    case selection = "selection"     // Select, highlight — Green (0.0, 1.0, 0.0)
    case edit = "edit"               // Undo, redo, modify — Blue (0.4, 0.7, 1.0)
    case destructive = "destructive" // Delete, cut — Red (1.0, 0.2, 0.2)
    case file = "file"               // Save, load — Purple (0.8, 0.4, 1.0)
    
    var color: (red: Double, green: Double, blue: Double) { ... }
    var displayName: String { ... }
}
```

### Requirements
- ✓ Identifiable by rawValue (string)
- ✓ Codable for persistence
- ✓ Each has descriptive displayName for UI
- ✓ Each has precise RGB tuple for rendering
- ✓ Hashable for use in collections

---

## ActionTrigger Struct

```swift
public struct ActionTrigger: Codable, Identifiable, Hashable {
    public var id: UUID
    public var eventDescription: String  // e.g., "Middle Drag", "⌘ + Z", "Scroll Up"
    
    public init(id: UUID = UUID(), eventDescription: String) {
        self.id = id
        self.eventDescription = sanitizeString(eventDescription, maxLength: 256)
    }
}
```

### Requirements
- ✓ Unique ID for tracking
- ✓ Human-readable event description
- ✓ Input sanitized (remove control chars, limit 256)
- ✓ Custom Codable conformance for validation on decode
- ✓ Identifiable by UUID
- ✓ Hashable for use in Sets/Dicts

### Examples
- "Middle Drag"
- "⌘ + Z"
- "Left Click"
- "Scroll Up"
- "Right Click"
- "Ctrl + Shift + A"
- "Space Bar"

---

## ActionMapping Struct

```swift
public struct ActionMapping: Codable, Identifiable, Hashable {
    public var id: UUID
    public var trigger: ActionTrigger
    public var label: String          // 1-8 chars displayed on overlay
    public var colorCategory: ColorCategory
    
    public init(
        id: UUID = UUID(),
        trigger: ActionTrigger,
        label: String,
        colorCategory: ColorCategory = .default
    ) {
        self.id = id
        self.trigger = trigger
        self.label = sanitizeString(label, maxLength: 8)
        self.colorCategory = colorCategory
    }
    
    // Legacy support for old action format
    public init(
        id: UUID = UUID(),
        action: String,
        label: String,
        colorCategory: ColorCategory = .default
    ) {
        self.id = id
        self.trigger = ActionTrigger(eventDescription: action)
        self.label = sanitizeString(label, maxLength: 8)
        self.colorCategory = colorCategory
    }
}
```

### Requirements
- ✓ Unique ID
- ✓ Trigger (ActionTrigger, not plain String)
- ✓ Label 1-8 characters (auto-sanitized)
- ✓ Color category (semantic grouping)
- ✓ Backward compatible with old action-based format
- ✓ Custom Codable supporting both old/new formats

### Validation Rules
- Label cannot be empty
- Label max 8 characters (enforced in setter)
- No two mappings with same trigger in a profile (validation in editor)

---

## Profile Struct

```swift
public struct Profile: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var mappings: [ActionMapping]
    public var isCustom: Bool  // false = built-in, true = user-created
    
    public init(
        id: UUID = UUID(),
        name: String,
        mappings: [ActionMapping] = [],
        isCustom: Bool = true
    ) {
        self.id = id
        self.name = sanitizeString(name, maxLength: 128)
        self.mappings = mappings
        self.isCustom = isCustom
    }
}
```

### Requirements
- ✓ Unique ID for identity
- ✓ Human-readable name (1-128 chars, sanitized)
- ✓ Array of ActionMappings (0 or more)
- ✓ isCustom flag (read-only after creation)
- ✓ Cannot delete built-in profiles (UI + code validation)
- ✓ Can rename custom profiles
- ✓ Can duplicate any profile

---

# PART 3: SETTINGS STORE SPECIFICATION

## SettingsStore Enhancements

### New @Published Property

```swift
@Published var currentProfile: Profile? = nil
```

- Tracks currently active profile
- Observed by LabelEngine and SettingsView
- Updated when user switches profiles or creates new one

### New Methods

#### addProfile(named: String)
```swift
func addProfile(named name: String = "New Profile") {
    let uniqueName = uniqueProfileName(basedOn: name)
    let newProfile = Profile(name: uniqueName, mappings: [], isCustom: true)
    profiles.append(newProfile)
    save()
}
```
- Creates new custom profile
- Auto-generates unique name if collision
- Empty mappings initially
- Immediately persisted

#### deleteProfile(at: Int)
```swift
func deleteProfile(at index: Int) {
    guard index >= 0 && index < profiles.count else { return }
    guard profiles[index].isCustom else { return }  // Prevent built-in deletion
    
    let deletedProfile = profiles.remove(at: index)
    
    if currentProfile?.id == deletedProfile.id {
        currentProfile = profiles.first
        activeProfileID = currentProfile?.id.uuidString ?? ""
    }
    save()
}
```
- Only custom profiles can be deleted
- If deleting active profile, switch to first available
- Persisted immediately

#### duplicateProfile(_ profile: Profile)
```swift
func duplicateProfile(_ profile: Profile) {
    let copy = Profile(
        name: uniqueProfileName(basedOn: profile.name + " copy"),
        mappings: profile.mappings,
        isCustom: true
    )
    profiles.append(copy)
    save()
}
```
- Clones entire profile including all mappings
- New profile gets unique name
- Always marked as custom
- Persisted immediately

#### renameProfile(_ profile: Profile, to: String)
```swift
func renameProfile(_ profile: Profile, to newName: String) {
    guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
    let sanitizedName = uniqueProfileName(basedOn: newName)
    
    var updated = profiles[idx]
    updated.name = sanitizedName
    profiles[idx] = updated
    
    if currentProfile?.id == profile.id {
        currentProfile = updated
    }
    save()
}
```
- Allows renaming custom profiles only (code validation)
- Auto-resolves name collisions
- Updates currentProfile if renaming active profile
- Persisted immediately

#### updateMappings(for profile: Profile, mappings: [ActionMapping])
```swift
func updateMappings(for profile: Profile, mappings: [ActionMapping]) {
    guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
    
    var updated = profiles[idx]
    updated.mappings = mappings
    profiles[idx] = updated
    
    if currentProfile?.id == profile.id {
        currentProfile = updated  // Notify observers
    }
    save()
}
```
- Replaces entire mapping array for a profile
- Validates mappings before persistence
- Updates currentProfile for reactive updates
- Persisted immediately

#### setActiveProfile(_ profile: Profile)
```swift
func setActiveProfile(_ profile: Profile) {
    activeProfileID = profile.id.uuidString
    currentProfile = profile
    objectWillChange.send()  // Notify all observers
}
```
- Switches active profile
- Updates AppStorage and @Published
- Notifies all subscribers

### Persistence Requirements

**File Location:**
```
~/Library/Application Support/TutorCast/profiles.json
```

**Encryption:**
- Algorithm: AES-256-GCM (CryptoKit)
- Key Storage: Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Key Size: 256-bit
- Key Generation: On first app launch, stored in Keychain
- Key Reuse: Same key for all profiles (app lifetime)

**First Launch:**
1. Check if profiles.json exists
2. If not: Create default set (AutoCAD, Photoshop, Default)
3. Set AutoCAD as active
4. Encrypt and persist

**Every Launch:**
1. Load and decrypt profiles.json
2. Update built-in profile mappings (ensure latest)
3. Maintain custom profiles unchanged
4. Load currentProfile from activeProfileID

**On Modify:**
1. Update in-memory profiles array
2. Encrypt full array to JSON
3. Write atomically to file

---

# PART 4: LABEL ENGINE SPECIFICATION

## LabelEngine Enhancements

### New @Published Property

```swift
@Published var colorCategory: ColorCategory = .default
```

Tracks the color category of current label. Updated alongside currentLabel.

### Enhanced Processing Logic

```swift
private func processEvent(_ eventDescription: String) {
    // 1. Normalize event for consistent matching
    let normalizedInput = normalizeEventDescription(eventDescription)
    
    // 2. Get current profile
    guard let activeProfile = settingsStore.currentProfile ?? settingsStore.activeProfile() else {
        currentLabel = sanitizeEventDisplay(eventDescription)
        colorCategory = .default
        scheduleAutoClear()
        return
    }
    
    // 3. Search for exact match in active profile mappings
    if let mapping = activeProfile.mappings.first(where: { 
        normalizeEventDescription($0.trigger.eventDescription) == normalizedInput
    }) {
        currentLabel = mapping.label
        colorCategory = mapping.colorCategory
        scheduleAutoClear()
        return
    }
    
    // 4. No match: display sanitized raw event
    currentLabel = sanitizeEventDisplay(eventDescription)
    colorCategory = .default
    scheduleAutoClear()
}

private func normalizeEventDescription(_ desc: String) -> String {
    return desc
        .lowercased()
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

private func sanitizeEventDisplay(_ event: String) -> String {
    let cleaned = event.trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    
    if cleaned.count > 12 {
        return String(cleaned.prefix(12)) + "…"
    }
    return cleaned
}
```

### Matching Rules

1. **Exact Match Priority**:
   - Find first mapping where `trigger.eventDescription` matches input
   - Case-insensitive, whitespace-normalized comparison

2. **Fallback Behavior**:
   - If no match found, display raw event (sanitized)
   - Use .default color category
   - Show for 2 seconds then auto-clear

3. **Profile Observer**:
   - Subscribe to `settingsStore.$currentProfile`
   - When profile changes, reset display (label="Ready", category=.default)

### Display Duration

- Show label for **2 seconds** after event detection
- Use Timer (not DispatchQueue) for reliability
- Cancel previous timer before scheduling new one
- On deinit: invalidate timer

---

# PART 5: OVERLAY UI SPECIFICATION

## OverlayContentView Enhancements

### Adaptive Font Sizing

| Label Length | Font Size | Weight | Design | Padding | Features |
|---|---|---|---|---|---|
| 1-3 chars | 1.8× base | Bold | Default | 12v/16h | Tracking 0.5pt, Capsule BG |
| 4-5 chars | 1.2× base | Semibold | Rounded | 10v/14h | Status dot shown |
| >5 chars | 0.9× base | Semibold | Rounded | 8v/12h | Ellipsis if >12 raw |

### Capsule Styling (Short Labels Only)

Applies only when `labelLength <= 3` AND `colorCategory != .default`:

```swift
Capsule(style: .continuous)
    .fill(
        LinearGradient(
            gradient: Gradient(colors: [
                labelColorValue.opacity(0.15),
                labelColorValue.opacity(0.08)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    .overlay(
        Capsule(style: .continuous)
            .strokeBorder(
                labelColorValue.opacity(0.4),
                lineWidth: 1.5
            )
    )
    .shadow(color: labelColorValue.opacity(0.3), radius: 6, x: 0, y: 2)
```

### Color Mapping

```swift
private var labelColorValue: Color {
    switch labelEngine.colorCategory {
    case .navigation:   return Color(red: 1.0, green: 0.6, blue: 0.0)
    case .zoom:         return Color(red: 0.0, green: 1.0, blue: 1.0)
    case .selection:    return Color(red: 0.0, green: 1.0, blue: 0.0)
    case .edit:         return Color(red: 0.4, green: 0.7, blue: 1.0)
    case .destructive:  return Color(red: 1.0, green: 0.2, blue: 0.2)
    case .file:         return Color(red: 0.8, green: 0.4, blue: 1.0)
    case .default:      return Color(nsColor: settingsStore.theme.textColor)
    }
}
```

### Layout

```
┌─────────────────────────────────────────┐
│  ● ZoomLabel                   (Capsule)│  ← 1-3 chars: large bold
│                                         │     Colored capsule background
│                                         │     Status dot visible
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  ● PanningMode                   (Pill)  │  ← 4-5 chars: medium
│                                         │     Normal border
│                                         │     Status dot visible
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  ● NavigationCommand             (Pill)  │  ← >5 chars: smaller
│                                         │     Normal border
│                                         │     Status dot visible
└─────────────────────────────────────────┘
```

### Animations

- Smooth transition when label changes: `animation(.easeInOut(duration: 0.15))`
- Smooth color transition: `animation(.easeInOut(duration: 0.15))`

---

# PART 6: SETTINGS UI SPECIFICATION

## SettingsView - Tabbed Interface

### Tabs
1. **Appearance** (Existing) - Theme, opacity, font size
2. **Profiles** (NEW) - Profile management UI
3. **Keyboard** - Shortcuts reference
4. **Permissions** - Input monitoring setup
5. **About** - Version info, links

### Window Sizing
- Width: 700 points (increased from 480)
- Height: 650 points (increased from default)
- Contains tabbed content

### Profiles Tab Content

Uses **ProfilesTabView** as content view.

---

## ProfilesTabView Specification

### Layout

```
┌──────────────────────────────────────────────────────┐
│ Profiles                          │                  │
│ Manage action shortcuts          │   Edit Profile    │
├────────────────────────────────┬──────────────────────┤
│                                │                      │
│ ○ AutoCAD              21       │ AutoCAD             │
│   (Built-in, locked)           │ Built-in Profile    │
│                                │ ✓ Active            │
│ ○ Photoshop            8        │                     │
│   (Built-in, locked)           │ Event  │ Label │ Cat│
│                                │ ┌─────────────────┐ │
│ ◉ My Custom            15       │ │ Middle Drag│ Pn│ │
│   (Custom, editable)            │ │ Scroll Up │ Z+│ │
│                                │ │ Left Click│Sel│ │
│ [ + New ] [ - Delete ] [ Dup ] │ └─────────────────┘ │
│                                │ [ Add Mapping ]    │
│                                │                    │
└────────────────────────────────┴────────────────────┘
```

### Left Sidebar

**Profile List Item:**
- Profile name (truncated if long)
- Mapping count (e.g., "21 actions")
- Lock icon if built-in
- Green checkmark if active
- Highlight background if selected

**Actions:**
- "+ New Profile" - Opens alert for name input
- "- Delete" - Only enabled if custom; shows confirmation
- "Duplicate" - Only enabled if custom

### Right Editor Panel

**Header Section:**
- Profile name (read-only display, or inline edit for custom)
- Active indicator (badge or button)
- Menu for "Edit Name" (custom only)

**Mapping Table:**
- Column 1: Event description (read-only, scrollable)
- Column 2: Label with color dot (edit pencil icon)
- Column 3: Category name (edit button)
- Column 4: Actions (edit pencil, delete trash)

**Row Interactions:**
- Click edit pencil → Open MappingEditorView modal
- Click delete → Confirmation dialog, then remove
- Right-click → Context menu with edit/delete (optional)

**Empty State:**
- Large icon + text: "No mappings yet"
- "Add your first action mapping" hint

**Add Button:**
- "+ Add Mapping" button at bottom
- Creates new ActionMapping with defaults
- Opens MappingEditorView modal for editing

---

## MappingEditorView Specification

### Modal Sheet Properties
- Size: 440 points wide, ~550 points tall
- Centered on screen
- Dismissible by clicking outside or "Cancel"

### Sections

#### 1. Input Event (Read-Only)

```
📥 Input Event
┌──────────────────────────┐
│ Middle Drag              │  ← read-only event description
│                          │
│ [ Recapture ]  [ Cancel ]│  ← if capturing: show progress
└──────────────────────────┘
```

- Shows captured event (e.g., "Middle Drag")
- "Recapture" button to re-listen (5-10 second timeout)
- "Listening for input…" text during capture

#### 2. Display Label

```
🏷 Display Label
  Short labels (1–3 chars) display best. Max 8 characters.
  
  ┌─────────────────────┐
  │ Pn                  │  ← text field, auto-truncate to 8
  └─────────────────────┘
  
  2/8 chars                   ✓ Perfect for overlay
```

- Text field with 8-char hard limit
- Real-time character counter (color-coded)
- Recommendation badge (Perfect / Good / Warning)

#### 3. Live Preview

```
Preview
┌─────────────────────────┐
│                         │
│          Pn             │  ← Large bold orange text
│                         │     (as will appear on overlay)
└─────────────────────────┘
```

- Renders label with exact styling
- Updates in real-time as user types
- Shows color category
- Shows adaptive font sizing

#### 4. Visual Category

```
🎨 Visual Category

  ⭕ Default
  🟠 Navigation (Orange)
  🔵 Zoom (Cyan)
  🟢 Selection (Green)
  🔵 Edit (Blue)
  🔴 Destructive (Red)
  🟣 File (Purple)
```

- Dropdown/Picker menu
- Color swatches next to each option
- Live preview updates when changed

#### 5. Validation & Buttons

```
⚠️ [Error message if invalid]

[ Cancel ]  [ Save ]  ← Save disabled if invalid
```

- Show red error if label is empty
- Show warning if label >5 chars ("May clutter overlay")
- Save button disabled until valid

### Validation Rules

1. Label cannot be empty
   - Trim whitespace
   - Show error: "Label cannot be empty"

2. Label max 8 characters
   - Auto-truncate in input field
   - Show error: "Maximum 8 characters"

3. Warn for long labels (>5 chars)
   - Yellow warning: "Longer labels may clutter overlay"
   - Allow save anyway (user's choice)

---

# PART 7: BUILT-IN PROFILES SPECIFICATION

## AutoCAD Profile (21 Mappings)

**Mouse & Navigation (Orange):**
| Event | Label | Category |
|---|---|---|
| Middle Drag | Pn | navigation |
| Left Click | Sel | selection |
| Right Click | Mnu | default |

**Zoom (Cyan):**
| Event | Label | Category |
|---|---|---|
| Scroll Up | Z+ | zoom |
| Scroll Down | Z- | zoom |
| Z | Zm | zoom |

**Edit (Blue):**
| Event | Label | Category |
|---|---|---|
| ⌘Z | U | edit |
| ⌘⇧Z | R | edit |
| E | Er | edit |

**Destructive (Red):**
| Event | Label | Category |
|---|---|---|
| Delete | Del | destructive |
| X | Cut | destructive |

**File (Purple):**
| Event | Label | Category |
|---|---|---|
| ⌘S | S | file |
| ⌘N | New | file |
| ⌘O | O | file |

**Drawing (Default):**
| Event | Label | Category |
|---|---|---|
| L | L | default |
| C | C | default |
| A | A | default |
| R | Rc | default |
| Escape | Esc | default |
| ⌘D | Dup | default |
| ⌘G | Grp | default |

## Photoshop Profile (8 Mappings)

| Event | Label | Category |
|---|---|---|
| B | Br | edit |
| E | Er | edit |
| V | Mv | default |
| M | Sel | selection |
| ⌘Z | U | edit |
| Space | Pn | navigation |
| ⌘+ | Z+ | zoom |
| ⌘- | Z- | zoom |

## Default Profile (4 Mappings)

| Event | Label | Category |
|---|---|---|
| Left Click | Clk | selection |
| Right Click | Mnu | default |
| Scroll Up | ↑ | default |
| Scroll Down | ↓ | default |

---

# PART 8: PERSISTENCE & MIGRATION

## Storage Architecture

### File Structure

```
~/Library/Application Support/TutorCast/
  ├── profiles.json           (encrypted JSON)
  └── (keychain stores encryption key)
```

### Encryption Strategy

**Algorithm:** AES-256-GCM (Galois/Counter Mode)

```swift
private func encryptData(_ data: Data) -> Data? {
    guard let key = loadOrCreateEncryptionKey() else { return nil }
    do {
        let sealedBox = try AES.GCM.seal(data, using: key)
        return sealedBox.combined  // IV + ciphertext + tag
    } catch { ... }
}

private func decryptData(_ encryptedData: Data) -> Data? {
    guard let key = loadOrCreateEncryptionKey() else { return nil }
    do {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: key)
    } catch { ... }
}
```

**Key Management:**

```swift
private func loadOrCreateEncryptionKey() -> SymmetricKey? {
    // 1. Query Keychain for existing key
    // 2. If found: return it
    // 3. If not found: generate new 256-bit key
    // 4. Store in Keychain with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    // 5. Return key
}
```

- Key never stored in UserDefaults or plain files
- Key accessible only when device is unlocked
- Key persists across app launches (automatic with Keychain)

### JSON Format

```json
[
  {
    "id": "A1B2C3D4-E5F6-47A9-8B4C-9D2E3F4A5B6C",
    "name": "AutoCAD",
    "isCustom": false,
    "mappings": [
      {
        "id": "X1Y2Z3W4-...",
        "trigger": {
          "id": "T1T2T3T4-...",
          "eventDescription": "Middle Drag"
        },
        "label": "Pn",
        "colorCategory": "navigation"
      }
    ]
  },
  {
    "id": "CUSTOM1-...",
    "name": "MyCAD",
    "isCustom": true,
    "mappings": [...]
  }
]
```

### Save Operation

```swift
func save() {
    if let data = try? JSONEncoder().encode(profiles),
       let encryptedData = encryptData(data) {
        try? encryptedData.write(to: fileURL, options: .atomic)
    }
}
```

- Atomic write (temp file + rename)
- Encryption before writing to disk
- Silent failure (log but don't crash)

### Load Operation

```swift
func load() {
    var loadedProfiles: [Profile] = []
    
    if let data = try? Data(contentsOf: fileURL), 
       let decryptedData = decryptData(data),
       let decoded = try? JSONDecoder().decode([Profile].self, from: decryptedData) {
        loadedProfiles = decoded
    } else {
        // First launch: seed defaults
        loadedProfiles = [
            BuiltInProfiles.autoCAD(),
            BuiltInProfiles.photoshop(),
            BuiltInProfiles.default()
        ]
        save()
    }
    
    // Always update built-in profiles
    updateBuiltInProfiles(&loadedProfiles)
    profiles = loadedProfiles
    
    if activeProfileID.isEmpty {
        activeProfileID = profiles.first?.id.uuidString ?? ""
    }
    
    currentProfile = profiles.first(where: { $0.id == UUID(uuidString: activeProfileID) })
}
```

### First Launch Behavior

1. App starts
2. SettingsStore.init() called → calls load()
3. profiles.json doesn't exist
4. Create default profiles: AutoCAD, Photoshop, Default
5. Set activeProfileID to AutoCAD's UUID
6. Encrypt and save to profiles.json
7. App uses AutoCAD profile for matching

### Every Launch Behavior

1. App starts
2. SettingsStore.init() called → calls load()
3. profiles.json exists and is valid
4. Decrypt and load all profiles
5. Update built-in profile mappings (ensure latest)
6. Maintain custom profiles unchanged
7. Restore active profile from activeProfileID
8. App ready to use

### Migration from Old Format

If old profiles exist (with just `action: String`):

```swift
// In ActionMapping.decode()
if let trigger = try? container.decode(ActionTrigger.self, forKey: .trigger) {
    self.trigger = trigger  // New format
} else if let actionStr = try? container.decode(String.self, forKey: .action) {
    self.trigger = ActionTrigger(eventDescription: actionStr)  // Migrate old
} else {
    throw DecodingError.dataCorrupted(...)
}
```

---

# PART 9: ERROR HANDLING & EDGE CASES

## Handled Scenarios

### Data Corruption
- **Scenario:** profiles.json is corrupted
- **Handling:** Catch decode error, seed defaults, save fresh
- **User Impact:** Zero (defaults loaded seamlessly)

### Profile Deletion
- **Scenario:** User deletes active profile
- **Handling:** Auto-switch to profiles.first
- **Validation:** setActiveProfile(profiles.first)
- **User Impact:** Seamless, no crash

### Name Collision
- **Scenario:** Create profile with existing name
- **Handling:** uniqueProfileName() appends " 2", " 3"
- **Validation:** Loop until unique found
- **User Impact:** Name auto-adjusted, no error

### Empty Mapping Label
- **Scenario:** User tries to save mapping without label
- **Handling:** Save button disabled, error message shown
- **Validation:** if label.trimmingCharacters(in: .whitespaces).isEmpty { ... }
- **User Impact:** Cannot proceed, clear error

### Long Label Entry
- **Scenario:** User pastes 50 characters
- **Handling:** Auto-truncate to 8 in text field
- **Validation:** if newValue.count > 8 { label = String(newValue.prefix(8)) }
- **User Impact:** See label shrink in real-time, no error

### Duplicate Trigger in Profile
- **Scenario:** Two mappings with same event
- **Handling:** Last one wins (no validation currently)
- **Future:** Warn user during edit, suggest consolidation
- **User Impact:** One mapping overrides other (rare edge case)

### No Mappings in Profile
- **Scenario:** Profile created but no mappings added
- **Handling:** All raw events display as-is, no label match
- **UI:** Empty state message with "Add Mapping" hint
- **User Impact:** Functional, just no labels

### Built-in Profile Modification Attempt
- **Scenario:** Code tries to delete/rename built-in profile
- **Handling:** guard profiles[idx].isCustom else { return }
- **Validation:** Fails silently (no-op)
- **User Impact:** UI prevents action (disabled button)

### Profile File Permission Issue
- **Scenario:** Unable to write to Application Support folder
- **Handling:** try? encryptedData.write(...) silently fails
- **Recovery:** In-memory changes persist session, lost on restart
- **User Impact:** Data lost on crash (rare, but possible)

---

# PART 10: TESTING & VALIDATION

## Unit Tests

### Profile Model
- [ ] ColorCategory has all 7 cases with correct RGB values
- [ ] ActionTrigger sanitizes input (max 256 chars)
- [ ] ActionMapping auto-truncates label to 8 chars
- [ ] Profile with isCustom=true cannot equal isCustom=false
- [ ] Built-in profile decode/encode preserves mappings

### SettingsStore
- [ ] addProfile() creates unique names
- [ ] deleteProfile() removes only custom
- [ ] duplicateProfile() copies all mappings
- [ ] renameProfile() prevents collisions
- [ ] updateMappings() persists to file
- [ ] load() seeds defaults on first run
- [ ] save() encrypts before writing

### LabelEngine
- [ ] processEvent() normalizes event description
- [ ] normalizeEventDescription() handles case/whitespace
- [ ] Found match: display mapping.label + colorCategory
- [ ] No match: display sanitized raw event + .default color
- [ ] Auto-clear timer fires after 2 seconds

### OverlayContentView
- [ ] 1-char label: font = 1.8× base, bold
- [ ] 3-char label: font = 1.8× base, bold, capsule background
- [ ] 5-char label: font = 1.2× base, semibold
- [ ] 8-char label: font = 0.9× base, semibold
- [ ] Color categories map correctly to RGB
- [ ] Animations smooth when label changes

## Integration Tests

- [ ] Create profile → appears in sidebar immediately
- [ ] Edit mapping → preview updates in real-time
- [ ] Save mapping → table updates, data persists
- [ ] Delete mapping → row disappears immediately
- [ ] Activate profile → LabelEngine uses new profile
- [ ] Perform action → overlay shows new profile's label
- [ ] Restart app → all data restored, active profile preserved
- [ ] Duplicate profile → copy has all mappings

## UI/UX Tests

- [ ] Modal opens/closes smoothly
- [ ] Sidebar selection highlights correctly
- [ ] Save button disabled when label empty
- [ ] Character counter updates in real-time
- [ ] Live preview reflects font size changes
- [ ] Color picker updates preview immediately
- [ ] Long label warning displays correctly
- [ ] Empty state shows when no mappings
- [ ] Delete confirmation dialog appears
- [ ] Name edit mode works inline

## Stress Tests

- [ ] Create 100 profiles → no performance impact
- [ ] Add 1000 mappings to one profile → save/load speed acceptable
- [ ] Rapidly switch profiles 50 times → no crashes
- [ ] Edit label character-by-character → smooth updates
- [ ] Crash during save → recover gracefully on relaunch

---

# PART 11: PERFORMANCE CONSIDERATIONS

## Memory
- Each Profile ~2KB base + mappings
- Each ActionMapping ~200 bytes (ID + strings)
- 100 profiles × 20 mappings × 200 bytes = 400KB (acceptable)

## CPU
- Event matching: O(n) linear search per event (n = mappings in profile)
- For 100 mappings: 100 comparisons per event (~1ms on modern Mac)
- Acceptable for realtime overlay updates

## Storage
- Encrypted profiles.json: ~20KB typical (100 profiles)
- Keychain key: 32 bytes (256-bit)
- Total: <1MB including app

## Optimization Strategies (if needed)
- Implement mapping index (HashMap) for O(1) lookup
- Cache normalized event descriptions
- Batch save changes (debounce)
- Lazy load large profiles (not needed initially)

---

# PART 12: SECURITY ANALYSIS

## Input Sanitization
- ✓ All strings limited to max length
- ✓ Control characters removed
- ✓ No shell metacharacters in labels
- ✓ No injection attacks possible

## Data Protection
- ✓ Encrypted at rest (AES-256-GCM)
- ✓ Encryption key in Keychain (protected)
- ✓ No credentials in plaintext
- ✓ No sensitive data in logs

## Access Control
- ✓ Cannot delete built-in profiles
- ✓ Cannot modify built-in profile names
- ✓ Custom profiles fully editable (owner)
- ✓ Active profile per user (AppStorage)

## Potential Vulnerabilities & Mitigations
| Threat | Mitigation |
|---|---|
| File tampering | Encryption invalidates tampering |
| Key exposure | Keychain protection, accessibility flags |
| Injection via label | Input sanitization, 8-char limit |
| Duplicate triggers | Last-write-wins (acceptable) |
| Denial of service | Bounded array sizes, UI prevents spam |

---

# PART 13: DEPLOYMENT CONSIDERATIONS

## Compatibility
- ✓ macOS 14.0+ (uses SwiftUI 5.0)
- ✓ Swift 6 (modern syntax)
- ✓ Xcode 16+ (recommended)

## Dependencies
- ✓ None external (CryptoKit is standard library)

## Configuration
- ✓ No user configuration needed
- ✓ App auto-creates defaults on first launch

## Rollout Strategy
1. Beta test with 10-20 content creators
2. Gather feedback on label recommendations
3. Refine built-in profiles based on usage data
4. General release to all users
5. Document feature in tutorials

---

# CONCLUSION

This comprehensive specification provides complete design guidance for implementing custom user profiles in TutorCast. The implementation prioritizes:

✅ **User Experience:** Short labels, color coding, adaptive typography  
✅ **Data Integrity:** Encrypted persistence, validation, migration  
✅ **Developer Quality:** Type safety, no external dependencies, best practices  
✅ **Security:** Input sanitization, key protection, access control  

All components work together seamlessly to deliver a professional-grade action annotation system for tutorial creators.
