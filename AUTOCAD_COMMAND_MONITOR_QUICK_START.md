# AutoCAD Command Monitor - Quick Start Guide

## Build & Test

### Prerequisites
- macOS 14.0+
- Xcode 15+
- AutoCAD for macOS (any recent version)
- Permissions: Input Monitoring + Accessibility

### Build Steps

1. **Open Xcode Project**
   ```bash
   cd /Users/nana/Documents/ISO/TutorCast
   open TutorCast.xcodeproj
   ```

2. **Update Bundle ID** (if needed)
   - Edit Info.plist or Xcode target settings
   - Set to: `com.yourteam.TutorCast`

3. **Build**
   ```bash
   ⌘B (Xcode)
   ```
   Or from terminal:
   ```bash
   xcodebuild -scheme TutorCast -configuration Debug
   ```

4. **Run**
   ```bash
   ⌘R (Xcode)
   ```
   Or:
   ```bash
   xcodebuild -scheme TutorCast -configuration Debug -derivedDataPath /tmp/build -resultBundlePath /tmp/result.xcresult
   ```

### Permission Grants (First Launch)

When TutorCast launches for the first time:

1. **Input Monitoring Dialog**
   - System Settings opens automatically
   - Navigate to: Privacy & Security → Input Monitoring
   - ✓ Enable TutorCast

2. **Accessibility Dialog** (may also appear)
   - System Settings opens automatically
   - Navigate to: Privacy & Security → Accessibility
   - ✓ Enable TutorCast

3. **Restart TutorCast**
   - Close and reopen the app
   - CGEventTap and AutoCADCommandMonitor will now start

### Testing with AutoCAD

#### Test 1: Command Detection
```
1. Open AutoCAD
2. Start TutorCast (Ctrl+Alt+Cmd+K to toggle overlay)
3. Type "L" (Line command)
   Expected: Overlay shows "LINE" + "Specify first point:"
4. Press Esc to cancel
   Expected: Overlay clears or shows "Ready"
```

#### Test 2: Subcommand Updates
```
1. Type "L" again
   Expected: "LINE" + "Specify first point:"
2. Click/type first point
   Expected: Prompt updates to "Specify next point or [Undo]:"
3. Click/type second point
   Expected: Prompt updates to "Specify next point or [Close/Undo]:"
```

#### Test 3: Command Switching
```
1. Type "OFFSET"
   Expected: Overlay shows "OFFSET" + "Select object to offset..."
2. Select an object
   Expected: Prompt updates
3. Type "LINE"
   Expected: Command switches to "LINE" + new prompt
```

#### Test 4: Long Prompts
```
1. Type "HATCH"
   Expected: "HATCH" + "Select boundaries or [Internal point/Associativity..."
   - If prompt is >100 chars, it should truncate with "…"
```

#### Test 5: Permission Denial
```
1. Revoke Accessibility permission:
   - System Settings → Accessibility → Uncheck TutorCast
2. Restart TutorCast
   Expected: 
   - Overlay works (keyboard mode)
   - Console shows: "⚠️  Could not access AutoCAD via Accessibility API"
   - No crash, graceful fallback
```

### Console Debugging

Watch the console output while testing:

```bash
# In Xcode: Product → Scheme → Edit Scheme → Run → Console
# Or terminal:
log stream --process=TutorCast 2>&1 | grep AutoCAD
```

**Expected console output:**
```
[AutoCADCommandMonitor] Starting command monitor...
[AutoCADCommandMonitor] ✅ Detected native macOS AutoCAD
[NativeMacOSAutoCADReader] Found AutoCAD app
[NativeMacOSAutoCADReader] Found command line element
[AutoCADCommandMonitor] Monitoring started
[LabelEngine] Command updated: LINE
```

**Error messages to watch for:**
```
[AutoCADCommandMonitor] ⚠️  No AutoCAD detected. Falling back to keyboard-only mode.
→ This is OK if AutoCAD isn't running

[AutoCADCommandMonitor] ⚠️  Helper process not responding
→ This is expected for Parallels (helper not implemented yet)

[NativeMacOSAutoCADReader] Error reading native AutoCAD state: ...
→ Check permissions or app focus
```

### Quick Debug Checklist

| Issue | Diagnostic Command | Solution |
|-------|---|---|
| Permission denied | `codesign -dv /path/to/TutorCast.app` | Grant Accessibility permission |
| AutoCAD not found | `ps aux \| grep autocad` | Launch AutoCAD first |
| Command not updating | `log stream \| grep AutoCAD` | Check console for errors |
| Overlay not showing | Ctrl+Alt+Cmd+K | Toggle overlay visibility |
| High CPU usage | Activity Monitor | May indicate polling issue |

### Performance Profiling

To profile the command monitor:

1. **In Xcode:**
   - Product → Profile
   - Select "System Trace" or "Time Profiler"
   - Record 10-30 seconds of use
   - Look for `AutoCADCommandMonitor`, `NativeMacOSAutoCADReader`

2. **Expected profile:**
   - AutoCADCommandMonitor: <5% CPU
   - AX element operations: <1% CPU
   - Total: <0.5% baseline (native reader)

### Log Levels

To enable verbose logging, you can modify:

**AutoCADCommandMonitor.swift:**
```swift
// Change this line:
print("[AutoCADCommandMonitor] Starting command monitor...")

// To enable more frequent logs:
if isMonitoring {
    print("[AutoCADCommandMonitor] Poll #\(pollCount): command='\(commandName)' subcommand='\(subcommandText)'")
}
```

### Testing on Parallels (Future)

Once Windows helper is implemented:

1. **Setup Windows VM**
   - Copy TutorCastHelper.exe to Windows
   - Create Task Scheduler entry to auto-start
   - Verify it starts when Windows boots

2. **Test from macOS**
   ```
   1. Verify Parallels Desktop is running
   2. Verify Windows VM is running
   3. Verify AutoCAD is running in Windows
   4. macOS should auto-detect and connect
   5. Same testing flow as native (commands 1-5 above)
   ```

3. **Debug Parallels connection**
   ```bash
   # macOS side
   nc -zv 127.0.0.1 24680  # Should connect if helper running
   
   # Windows side (in VM)
   netstat -an | findstr 24680  # Check if listening
   ```

---

## Common Issues & Solutions

### Issue: "CGEventTap creation failed"
**Cause:** Input Monitoring permission not granted  
**Fix:** Grant permission as per steps above, restart app

### Issue: "Could not access AutoCAD via Accessibility API"
**Cause:** Accessibility permission not granted  
**Fix:** Grant permission, restart app

### Issue: Overlay shows "Ready" always
**Cause:** AutoCAD not detected or running  
**Fix:** Make sure AutoCAD is the active app

### Issue: Command shows but subcommand doesn't
**Cause:** Command line text not formatted as expected  
**Fix:** Check console for parsing errors, may need to adjust regex

### Issue: High memory usage
**Cause:** AX element cache not being cleared  
**Fix:** Manual cache clear not needed (5-sec TTL), restart app if persists

### Issue: Parallels helper not connecting
**Cause:** Helper not running in Windows VM  
**Fix:** Windows helper not yet implemented — this is expected

---

## Release Checklist

Before shipping:

- [ ] All tests pass with native AutoCAD
- [ ] Permissions flow works correctly
- [ ] No console errors in Release build
- [ ] Performance: <1% CPU at baseline
- [ ] Documentation reviewed
- [ ] Notarization requirements met
- [ ] Code signed with developer certificate

---

## Next Steps

1. **Validate on your machine** following Test 1-5 above
2. **Create test case documentation** for your setup
3. **Implement Windows helper** (when ready) using WINDOWS_HELPER_IMPLEMENTATION.md
4. **Submit for code review** if in team setting

---

## Support

For issues or questions:
1. Check the error message in console
2. Review AUTOCAD_COMMAND_MONITOR_FEATURE.md for architecture details
3. Review WINDOWS_HELPER_IMPLEMENTATION.md for Parallels-specific issues
4. Enable verbose logging as described above

---

**Last Updated:** March 2026
**Status:** Ready for testing with native macOS AutoCAD
