# Quick Start: Connecting TutorCast to AutoCAD in Parallels

## 🚀 5-Minute Setup

### Prerequisites
- TutorCast app built and running (✓ Already done!)
- Parallels Desktop with Windows VM running
- AutoCAD installed on Windows VM
- Network: VM and macOS on same subnet

---

## Quick Setup Steps

### 1. **Identify Your VM IP** (2 min)

From macOS Terminal:
```bash
# Find your VM
prlctl list

# Get VM IP (replace "Windows" with your VM name)
prlctl exec Windows ipconfig
```

**Look for:** `IPv4 Address: 192.168.1.x` (or similar)

**Example:** `192.168.1.105`

---

### 2. **Deploy Plugin to VM** (2 min)

Automated deployment:
```bash
cd /Users/nana/Documents/ISO/TutorCast
./deploy_plugin.sh
```

**Or manually:**
```bash
# Copy plugin to Windows VM
scp Plugins/Windows/TutorCastPlugin.exe user@192.168.1.105:C:\\Users\\user\\AppData\\Local\\TutorCast\\
```

---

### 3. **Load Plugin in AutoCAD** (1 min)

On Windows VM:
1. Open **AutoCAD**
2. Go to **Tools** → **Load Application**
3. Browse to: `C:\Users\user\AppData\Local\TutorCast\TutorCastPlugin.exe`
4. Click **Load**
5. Close dialog

**Or via command line (PowerShell on VM):**
```powershell
# Run once to load
C:\Users\user\AppData\Local\TutorCast\TutorCastPlugin.exe
```

---

### 4. **Test Connection** (0 min)

```bash
# From macOS, test if port 19848 is open
nc -zv 192.168.1.105 19848

# Should show: Connection succeeded
```

---

### 5. **Verify It Works** (optional)

1. Launch **TutorCast** on macOS
2. In AutoCAD on Windows, type: `LINE` and press Enter
3. Watch TutorCast overlay on macOS
4. Should display: `LIN` with color coding

✅ **Success!**

---

## Troubleshooting

### "Port connection refused"
```bash
# On Windows VM (PowerShell as Admin):
netsh advfirewall firewall add rule name="TutorCast" dir=in action=allow protocol=tcp localport=19848

# Restart AutoCAD to reload plugin
```

### "Can't find VM"
```bash
# Make sure IP is correct
prlctl exec Windows ipconfig | grep "IPv4 Address"

# Update TutorCast settings
defaults write com.tutorcast.app AutoCADParallelsIP "192.168.1.105"
```

### "Nothing shows in overlay"
```bash
# Check if plugin loaded
# In AutoCAD, look in command line for: [TutorCast] Plugin initialized

# Check logs
log stream --predicate 'process == "TutorCast"' --level debug
```

---

## Full Diagnostic

If quick setup doesn't work:

```bash
./diagnose_connection.sh
```

This will check:
- ✓ TutorCast app running
- ✓ VM IP configured
- ✓ Network connectivity
- ✓ Port listening
- ✓ Plugin status
- ✓ Recent logs

---

## Manual Testing

### Test 1: Verify VM is reachable
```bash
ping 192.168.1.105
# Should respond
```

### Test 2: Check port is open
```bash
nc -zv 192.168.1.105 19848
# Should show: Connection succeeded

# Or using Telnet
telnet 192.168.1.105 19848
# CTRL+C to exit
```

### Test 3: Send test event
```bash
# From macOS, send a test command
echo '{"type":"test","commandName":"TEST"}' | nc 192.168.1.105 19848
```

### Test 4: Check TutorCast logs
```bash
log stream --predicate 'process == "TutorCast"' --level debug | grep -i "listener\|connect"
```

### Test 5: Check Windows plugin
```bash
# On Windows VM (PowerShell)
netstat -an | findstr 19848
# Should show: LISTENING

# Check AutoCAD console for plugin output
```

---

## Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| "Connection refused" | Port 19848 not open. Check Windows Firewall. |
| "Connection timeout" | VM IP wrong or VM not running. Verify IP. |
| "No events received" | Plugin not loaded in AutoCAD. Use Tools → Load Application. |
| "Overlay doesn't update" | Check TutorCast logs for validation errors. |
| "Port already in use" | Another app using 19848. Change port or restart VM. |

---

## What Happens Next

Once connected:

1. **AutoCAD command starts** (e.g., `LINE`)
2. **Plugin detects** via UI Automation
3. **Plugin sends JSON** to port 19848
4. **TutorCast receives** via AutoCADParallelsListener
5. **SecurityValidator validates** command format
6. **LabelEngine processes** and displays
7. **Overlay updates** with command name + category color
8. **Auto-clear** when command completes

**Latency:** ~50-100ms from command start to overlay display

---

## System Info

**macOS Side:**
- App: TutorCast
- Listener: AutoCADParallelsListener.swift
- Port: 19848 (listening)
- Protocol: TCP, JSON-encoded events

**Windows Side (Parallels VM):**
- Plugin: TutorCastPlugin.exe (.NET/C#)
- Port: 19848 (client)
- Protocol: TCP, JSON-encoded events
- Location: `C:\Users\user\AppData\Local\TutorCast\`

---

## Advanced: Custom Configuration

### Change Port
```bash
# macOS: defaults write com.tutorcast.app AutoCADParallelsPort 19849
# Windows Plugin: Change port in source code
```

### Change VM IP Manually
```bash
defaults write com.tutorcast.app AutoCADParallelsIP "192.168.1.110"
```

### Enable Debug Logging
```bash
defaults write com.tutorcast.app DebugMode YES
log stream --predicate 'process == "TutorCast"' --level debug
```

### Disable Auto-Detection
```bash
defaults write com.tutorcast.app ForceParallelsMode YES
```

---

## Next: Test Advanced Features

1. **Try more commands:**
   - OFFSET, HATCH, COPY, ROTATE, MOVE
   - Verify category colors match profile mapping

2. **Test subcommands:**
   - Watch overlay update as you're prompted
   - Verify option display in secondary label

3. **Performance test:**
   - Rapid commands to measure latency
   - Monitor CPU/network usage

4. **Edge cases:**
   - Long command names (verify truncation)
   - Special characters (verify sanitization)
   - Keyboard-only mode (if plugin fails)

---

## Support Resources

- **Full Guide:** [PLUGIN_CONNECTION_GUIDE.md](PLUGIN_CONNECTION_GUIDE.md)
- **Diagnostics:** `./diagnose_connection.sh`
- **Deployment:** `./deploy_plugin.sh`
- **Architecture:** See TutorCast source files

---

**Good luck! 🎉**

For issues or questions, check the diagnostic logs or review the full connection guide.
