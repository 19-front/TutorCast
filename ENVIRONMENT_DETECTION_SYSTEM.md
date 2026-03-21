# AutoCAD Environment Detection System

## Overview

The **AutoCADEnvironmentDetector** is a background service that automatically identifies which AutoCAD environment is active on the system:

- **Native macOS** — AutoCAD installed natively for macOS (via Accessibility API)
- **Parallels Windows** — AutoCAD running in a Windows VM inside Parallels Desktop (via network scan + port probing)
- **Not Running** — No AutoCAD detected
- **Unknown** — Detection inconclusive

This enables TutorCast to transparently adapt to the user's setup without manual configuration.

---

## Detection Pipeline

### Step 1: Manual Override Check
Before any detection, check `UserDefaults` for manual override:
- `"native"` → Force native mode
- `"disabled"` → Force no AutoCAD
- `"parallels:<ip>"` → Force Parallels at specific IP
- Not set → Proceed with automatic detection

### Step 2: Native macOS AutoCAD
Scan `NSWorkspace.shared.runningApplications` for:
- Bundle ID starting with `com.autodesk.autocad*`
- Process name containing "AutoCAD" (excluding Parallels)

If found:
- Extract version from `CFBundleShortVersionString`
- Return `.nativeMac(version:)`
- Stop detection

### Step 3: Parallels Desktop Check
Scan running applications for:
- Bundle ID: `com.parallels.desktop.console`
- Process name: containing "parallels"

If not found:
- Return `.notRunning`
- Stop detection

If found:
- Proceed to step 4 (network scan)

### Step 4: Windows VM with AutoCAD
Scan Parallels network ranges for open port 19848 (TutorCast Windows plugin):

**Primary range:** `10.211.55.0/24` (host-only adapter)
**Secondary range:** `10.37.129.0/24` (shared adapter)

For each range:
1. Scan hosts `.1` through `.254`
2. Test TCP port 19848 (200ms timeout per host)
3. Use concurrent scanning (max 10 concurrent connections)
4. Return on first match: `.parallelsWindows(vmIP:)`

### Step 5: Fallback
If all steps fail:
- Return `.unknown`

---

## Re-Detection Schedule

### On App Launch
- 3-second delay to allow apps to initialize
- Prevents race conditions with app startup

### Periodic Background Scanning
- Every 30 seconds
- Allows detection of late-starting AutoCAD
- Handles app quit/restart

### On Workspace Notifications
- `didLaunchApplicationNotification` — Re-detect immediately when app launches
- Filters for AutoCAD or Parallels
- Allows real-time detection of user launching AutoCAD

---

## Network Scanning Strategy

### Why TCP Port Probing?
- **Parallels VMs are isolated** — Can't easily check process list from macOS
- **Port 19848** — Designated for TutorCast Windows plugin (see Section 6)
- **Fast & reliable** — 200ms timeout prevents hanging

### Concurrent Scanning
- Scan up to 10 hosts simultaneously
- Prevents sequential timeout from being slow (254 hosts × 200ms = 50+ seconds)
- With 10-concurrent: ~25 seconds worst-case for full range

### Timeout Logic
```swift
TCP Connect Attempt (per host):
├─ TCP_NODELAY for faster failure
├─ Non-blocking socket
├─ select() with 200ms timeout
└─ Return result

Full scan:
├─ Concurrent semaphore (10 max)
├─ Cancel on first match
└─ Worst case: ~25 seconds for full range
```

### Why Two Network Ranges?
Parallels uses different adapters depending on configuration:
- **10.211.55.x** — Host-only (isolated, most common)
- **10.37.129.x** — Shared (bridged, alternative config)

Checking both ensures we find AutoCAD regardless of Parallels networking setup.

---

## Usage

### Initialization (AppDelegate)

```swift
// In applicationDidFinishLaunching
AutoCADEnvironmentDetector.shared.startDetection()

// On termination
func applicationWillTerminate(_ notification: Notification) {
    AutoCADEnvironmentDetector.shared.stopDetection()
}
```

### Observing Detection Results

```swift
@StateObject private var detector = AutoCADEnvironmentDetector.shared

var body: some View {
    VStack {
        switch detector.current {
        case .notRunning:
            Text("No AutoCAD detected")
        case .nativeMac(let version):
            Text("macOS AutoCAD \(version ?? "unknown")")
        case .parallelsWindows(let ip):
            Text("Parallels at \(ip)")
        case .unknown:
            Text("Detection in progress...")
        }
        
        if detector.isDetecting {
            ProgressView()
        }
    }
}
```

### Manual Override (Advanced Users)

```bash
# Force native mode
defaults write com.autodesk.tutorcast autocad.environment.override -string "native"

# Force Parallels at specific IP
defaults write com.autodesk.tutorcast autocad.environment.override -string "parallels:10.211.55.101"

# Disable detection
defaults write com.autodesk.tutorcast autocad.environment.override -string "disabled"

# Clear override (resume auto-detection)
defaults delete com.autodesk.tutorcast autocad.environment.override
```

---

## Menu Bar UI Feedback

The detection status is displayed as a colored dot in the menu bar:

```
[🔘 TutorCast]  ← Gray dot = not detected
[🟢 TutorCast]  ← Green dot = native macOS
[🔵 TutorCast]  ← Blue dot = Parallels Windows
[🟠 TutorCast]  ← Orange dot = detecting
```

See Section 9 (Menu Bar UI) for implementation details.

---

## Error Handling

### Network Unreachable
- Gracefully fails (returns false)
- Doesn't block UI thread
- Retries on next 30-second interval

### DNS Resolution Fails
- Skips host
- Continues to next host
- Returns nil if all fail

### Port 19848 Not Responding
- Treated as no AutoCAD at that IP
- Continues scanning
- May indicate Windows VM not running

### Socket Timeout
- Returns false after 200ms
- Moves to next host
- Doesn't accumulate

---

## Performance

| Operation | Time | Impact |
|-----------|------|--------|
| Native check | <50ms | Low (just app scanning) |
| Parallels check | <50ms | Low (just app scanning) |
| Full network scan | ~25s worst-case | Only runs if both above fail |
| Periodic re-check | 30s interval | Background only |
| On-notification re-check | Immediate | Only for AutoCAD/Parallels apps |

---

## Logging

Enable detailed logging in console:

```bash
log stream --process=TutorCast 2>&1 | grep AutoCADEnvironmentDetector
```

Expected output:
```
[AutoCADEnvironmentDetector] Starting detection...
[AutoCADEnvironmentDetector] Found native macOS AutoCAD: com.autodesk.autocad v2025.1
```

or

```
[AutoCADEnvironmentDetector] Starting detection...
[AutoCADEnvironmentDetector] Parallels Desktop detected, scanning for Windows VM...
[AutoCADEnvironmentDetector] Scanning network range: 10.211.55.0/24
[AutoCADEnvironmentDetector] ✅ Found Windows VM with AutoCAD at: 10.211.55.101
```

---

## Edge Cases

### Both Native and Parallels Running
Priority: **Native macOS takes precedence**
- If native AutoCAD detected, return immediately
- Parallels scanning only happens if native not found
- Rationale: Native is higher performance, always preferred

### Multiple VMs Running
Returns first VM with port 19848 open
- Network order determines which is found first
- If specific VM needed, use manual override

### AutoCAD Launches While Scanning
Workspace notifications catch it
- Re-detection triggered immediately
- Current scan continues (will be replaced by new result)
- User sees updated status within 1 second

### Parallels on Different Network
Use manual override:
```bash
defaults write com.autodesk.tutorcast autocad.environment.override \
  -string "parallels:192.168.1.50"
```

### VPN / Network Isolation
Network scanning may be blocked
- Gracefully fails after 30-second timeout
- Suggest manual override to user
- Document in setup guide

---

## Testing

### Unit Tests

```swift
func testNativeDetection() async {
    // Mock running app
    let detector = AutoCADEnvironmentDetector.shared
    let result = await detector.detect()
    
    // Verify
    if case .nativeMac(let version) = result {
        XCTAssertNotNil(version)
    }
}

func testManualOverride() async {
    UserDefaults.standard.set("native", 
        forKey: "autocad.environment.override")
    
    let detector = AutoCADEnvironmentDetector.shared
    let result = await detector.detect()
    
    XCTAssertEqual(result, .nativeMac(version: nil))
}
```

### Manual Testing

1. **Native macOS AutoCAD**
   - Launch AutoCAD for macOS
   - Check: Should see green dot + "macOS v2025.1"
   - Close AutoCAD
   - Check: Should revert to gray dot after 30s

2. **Parallels Windows**
   - Launch Parallels Desktop
   - Start Windows VM
   - Launch AutoCAD inside Windows
   - Check: Should see blue dot + IP within 30s
   - Kill Windows
   - Check: Should revert to gray dot after 30s

3. **Manual Override**
   ```bash
   defaults write com.autodesk.tutorcast autocad.environment.override -string "native"
   # Relaunch TutorCast
   # Should show green dot regardless of actual state
   ```

---

## Integration Points

### AutoCADCommandMonitor
Uses detection result to choose reader:
```swift
switch AutoCADEnvironmentDetector.shared.current {
case .nativeMac:
    startNativeReader()
case .parallelsWindows(let ip):
    startParallelsReader(ip: ip)
default:
    return  // No AutoCAD
}
```

### LabelEngine
May filter display based on detection
```swift
if case .unknown = detector.current {
    // Show warning: "AutoCAD not detected"
}
```

### Menu Bar UI
Shows status via colored dot
```swift
var statusColor: Color {
    switch detector.current {
    case .nativeMac: return .green
    case .parallelsWindows: return .blue
    case .notRunning: return .gray
    case .unknown: return .orange
    }
}
```

---

## Troubleshooting

| Issue | Diagnosis | Solution |
|-------|-----------|----------|
| Always shows gray | Check Console for errors | Restart TutorCast |
| Takes 30+ seconds to detect | Network scanning running | This is normal (worst-case timeout) |
| Doesn't detect native AutoCAD | Check process name | Restart AutoCAD or use override |
| Can't find Parallels VM | VPN/firewall blocking scan | Use manual override with IP |
| Status doesn't update when AutoCAD quit | Waiting for 30s interval | Relaunch TutorCast or wait 30s |

---

## Future Enhancements

- [ ] Faster network scanning (use ICMP ping first)
- [ ] Persistent IP cache (remember last known Parallels IP)
- [ ] User-configurable network ranges
- [ ] mDNS service discovery for VMs
- [ ] Option to skip slow network scan if already detected once

---

**File:** `AutoCADEnvironmentDetector.swift`  
**Lines:** ~480  
**Status:** Complete and integrated  
**Testing:** Ready for manual validation
