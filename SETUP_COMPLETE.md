# TutorCast Plugin Integration - Complete Setup Guide

## 📋 What You Have

✅ **TutorCast App** - macOS application (built successfully)  
✅ **AutoCADParallelsListener** - TCP server listening on port 19848  
✅ **AutoCADEnvironmentDetector** - Auto-detection of Parallels VM  
✅ **SecurityValidator** - Event validation and sanitization  
✅ **LabelEngine** - Command processing and display logic  
✅ **Plugins** - Windows .NET, macOS Python, AutoLISP fallback

---

## 🎯 Your Goal

Connect TutorCast to AutoCAD running in a **Parallels Desktop Windows VM** so that:

1. AutoCAD commands trigger plugin events
2. Plugin sends events to TutorCast via TCP
3. TutorCast displays commands on overlay in real-time
4. Overlay updates as subcommands/options change
5. Overlay clears when command completes

---

## 🗺️ Connection Flow

```
┌─────────────────────────┐
│  Windows VM (Parallels) │
│  ┌───────────────────┐  │
│  │     AutoCAD       │  │
│  │   (with plugin)   │  │
│  └─────────┬─────────┘  │
│            │ UI Events  │
│  ┌─────────▼─────────┐  │
│  │   Plugin (C#)     │  │
│  │ Formats as JSON   │  │
│  └─────────┬─────────┘  │
└────────────┼────────────┘
             │
             │ JSON Events
             │ TCP:19848
             │ (over network)
             │
┌────────────▼────────────┐
│  macOS TutorCast App    │
│  ┌───────────────────┐  │
│  │AutoCADParallels   │  │
│  │Listener (TCP)     │  │
│  └─────────┬─────────┘  │
│            │            │
│  ┌─────────▼─────────┐  │
│  │Security Validator │  │
│  │(Verify + Sanitize)│  │
│  └─────────┬─────────┘  │
│            │            │
│  ┌─────────▼─────────┐  │
│  │   LabelEngine     │  │
│  │(Process + Display)│  │
│  └─────────┬─────────┘  │
│            │            │
│  ┌─────────▼─────────┐  │
│  │  OverlayView      │  │
│  │(Render on screen) │  │
│  └───────────────────┘  │
└────────────────────────┘
```

---

## 🚀 Quick Setup (5 minutes)

### Step 1: Get VM IP (1 min)

```bash
prlctl exec Windows ipconfig | grep "IPv4 Address"
# Example output: 192.168.1.105
```

**Save this IP** - you'll need it!

### Step 2: Deploy Plugin (2 min)

**Automated:**
```bash
cd /Users/nana/Documents/ISO/TutorCast
./deploy_plugin.sh
```

**Or manually:**
```bash
scp Plugins/Windows/TutorCastPlugin.exe user@192.168.1.105:C:\\Users\\user\\AppData\\Local\\TutorCast\\
```

### Step 3: Load Plugin in AutoCAD (1 min)

On Windows VM in AutoCAD:
1. **Tools** → **Load Application**
2. Browse to: `C:\Users\user\AppData\Local\TutorCast\TutorCastPlugin.exe`
3. Click **Load**

### Step 4: Test Connection (1 min)

```bash
nc -zv 192.168.1.105 19848
# Should show: Connection succeeded
```

### Step 5: Try It!

1. Launch TutorCast on macOS
2. In AutoCAD: Type `LINE` and press Enter
3. Watch TutorCast overlay - should show command name and updates

---

## 📍 Key Files & Locations

### On macOS

| File | Purpose |
|------|---------|
| `/Applications/TutorCast.app` | Main app |
| `TutorCast/Models/AutoCADParallelsListener.swift` | TCP server (port 19848) |
| `TutorCast/Models/LabelEngine.swift` | Command processing |
| `TutorCast/Models/SecurityValidator.swift` | Event validation |
| `/Users/nana/Library/Preferences/com.tutorcast.app.plist` | Settings |

### On Windows VM

| File | Purpose |
|------|---------|
| `C:\Users\user\AppData\Local\TutorCast\TutorCastPlugin.exe` | Plugin executable |
| `C:\Users\user\AppData\Local\TutorCast\Logs\` | Plugin logs (if created) |
| AutoCAD command line | Plugin output & errors |

### Event Data

| Location | Purpose |
|----------|---------|
| `~/tutorcast_events/` | Shared event files (for fallback mode) |
| `/tmp/tutorcast_autocad.sock` | Unix socket (native macOS mode) |

---

## 🔧 Configuration

### Auto-Configuration
TutorCast automatically:
1. Scans network for port 19848
2. Detects VM IP address
3. Connects when plugin is loaded
4. Validates incoming events

### Manual Configuration (if needed)

```bash
# Set VM IP
defaults write com.tutorcast.app AutoCADParallelsIP "192.168.1.105"

# Set custom port (if not 19848)
defaults write com.tutorcast.app AutoCADParallelsPort 19849

# Force Parallels mode (skip auto-detection)
defaults write com.tutorcast.app ForceParallelsMode YES

# Enable debug logging
defaults write com.tutorcast.app DebugMode YES
```

---

## ✅ Verify Installation

### Test 1: Plugin Deployed
```bash
ssh user@192.168.1.105 "dir C:\\Users\\user\\AppData\\Local\\TutorCast\\"
# Should show: TutorCastPlugin.exe
```

### Test 2: Port Open
```bash
nc -zv 192.168.1.105 19848
# Should show: Connection succeeded
```

### Test 3: Plugin Running
```bash
ssh user@192.168.1.105 "netstat -an | findstr 19848"
# Should show: LISTENING
```

### Test 4: TutorCast Connecting
```bash
log stream --predicate 'process == "TutorCast"' --level debug | grep -i "connect"
# Should show: AutoCADParallelsListener connected events
```

### Test 5: Events Flowing
In AutoCAD, type: `LINE`  
In TutorCast overlay, should see: `LIN` with color

---

## 🐛 Troubleshooting

### "Port 19848 refused"
```bash
# On Windows VM, allow through firewall
netsh advfirewall firewall add rule name="TutorCast" dir=in action=allow protocol=tcp localport=19848

# Restart AutoCAD
```

### "Plugin won't load in AutoCAD"
```cmd
# Check .NET Framework version on Windows VM
dotnet --version  # Should be 4.7.2+

# Try loading plugin with explicit path
APPLOAD
C:\Users\user\AppData\Local\TutorCast\TutorCastPlugin.exe
```

### "No events received in TutorCast"
```bash
# Check TutorCast logs
log stream --predicate 'process == "TutorCast"' --level debug

# Check if plugin is sending JSON
echo '{"type":"test","commandName":"TEST"}' | nc 192.168.1.105 19848
```

### "Wrong VM detected"
```bash
# Verify VM IP
prlctl exec Windows ipconfig | grep IPv4

# Update if needed
defaults write com.tutorcast.app AutoCADParallelsIP "correct.ip.address"
```

---

## 📊 Diagnostic Tools

### Run Full Diagnostics
```bash
cd /Users/nana/Documents/ISO/TutorCast
./diagnose_connection.sh
```

This checks:
- ✓ TutorCast running
- ✓ VM IP configured
- ✓ Network connectivity
- ✓ Port listening
- ✓ Plugin loaded
- ✓ Recent events

### View Real-Time Logs
```bash
# macOS TutorCast logs
log stream --predicate 'process == "TutorCast"' --level debug

# Filter for listener events
log stream --predicate 'process == "TutorCast"' | grep -i "listener\|connect\|receive"

# Filter for validation errors
log stream --predicate 'process == "TutorCast"' | grep -i "validation\|reject\|error"
```

### Manual Connection Test
```bash
# Test sending event to plugin
echo '{"type":"commandStarted","commandName":"LINE","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","checksum":"abc123"}' | nc 192.168.1.105 19848
```

---

## 🌐 Event Format

### Example Event
```json
{
  "type": "commandStarted",
  "commandName": "LINE",
  "subcommand": "Specify first point:",
  "activeOptions": ["Undo"],
  "timestamp": "2026-03-21T14:30:00Z",
  "checksum": "a3f5b9e2c8d1e4f7..."
}
```

### Event Types
- `commandStarted` - User starts command
- `subcommandPrompt` - Prompt for option/input
- `optionSelected` - User selects option
- `commandCompleted` - Command finishes successfully
- `commandCancelled` - User cancels command (ESC)
- `commandLineText` - Raw fallback text

**Full Reference:** [EVENT_FORMAT_REFERENCE.md](EVENT_FORMAT_REFERENCE.md)

---

## 🎯 Testing Workflow

### Test 1: Basic Command
1. AutoCAD: `LINE` ↵
2. TutorCast: Should show `LIN`
3. Expected duration: 5 seconds

### Test 2: With Subcommand
1. AutoCAD: `OFFSET` ↵
2. AutoCAD: Click an object
3. TutorCast: Should show subcommand prompt
4. AutoCAD: `T` for "Through" option
5. TutorCast: Should flash "Through"

### Test 3: Completion
1. AutoCAD: Complete the command ↵
2. TutorCast: Label fades to "Ready"
3. Expected duration: 0.8 seconds

### Test 4: Multiple Commands
1. Repeat commands rapidly
2. Monitor for dropped events
3. Check overlay responsiveness
4. Verify no memory leaks in TutorCast

---

## 📈 Performance Expectations

| Metric | Expected | Acceptable |
|--------|----------|------------|
| Event latency | 50-100ms | < 500ms |
| Overlay update | 100-200ms | < 1s |
| Connection init | < 1s | < 5s |
| CPU usage | < 5% | < 15% |
| Memory (TutorCast) | 50-100MB | < 200MB |
| Memory (Plugin) | 20-50MB | < 100MB |

---

## 🔐 Security Notes

1. **Validation:** All events validated with SHA-256 checksums
2. **Sanitization:** Control characters removed, lengths checked
3. **Isolation:** Local network only (not exposed to internet)
4. **Permissions:** Socket with restricted permissions (0o600)
5. **Rate Limiting:** Max 100 events/second enforced

---

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| [QUICK_START_PLUGIN.md](QUICK_START_PLUGIN.md) | 5-minute setup guide |
| [PLUGIN_CONNECTION_GUIDE.md](PLUGIN_CONNECTION_GUIDE.md) | Detailed setup & troubleshooting |
| [EVENT_FORMAT_REFERENCE.md](EVENT_FORMAT_REFERENCE.md) | Event structure & API |
| [BUILD_SUCCESS.md](BUILD_SUCCESS.md) | Compilation fixes & status |

---

## ⚡ Quick Commands Reference

```bash
# Check VM IP
prlctl exec Windows ipconfig | grep IPv4

# Deploy plugin
cd /Users/nana/Documents/ISO/TutorCast && ./deploy_plugin.sh

# Test connection
nc -zv 192.168.1.105 19848

# View TutorCast logs
log stream --predicate 'process == "TutorCast"' --level debug

# Run diagnostics
./diagnose_connection.sh

# Configure manually
defaults write com.tutorcast.app AutoCADParallelsIP "192.168.1.105"
defaults write com.tutorcast.app AutoCADParallelsPort 19848

# Launch TutorCast
open /Applications/TutorCast.app
```

---

## ✨ What Happens After Connection

Once everything is set up:

1. **AutoCAD Command** (e.g., `LINE`)
   ↓
2. **Plugin Detects** (via UI Automation)
   ↓
3. **Plugin Sends JSON** (to port 19848)
   ↓
4. **TutorCast Receives** (via AutoCADParallelsListener)
   ↓
5. **Validator Checks** (security & format)
   ↓
6. **LabelEngine Processes** (maps to display)
   ↓
7. **Overlay Updates** (shows command name + color)
   ↓
8. **Timer Scheduled** (auto-clear after duration)
   ↓
9. **Command Completes**
   ↓
10. **Overlay Clears** (returns to "Ready")

**Total latency:** 50-200ms from command to display

---

## 🎓 Next Steps

1. ✅ **Deploy Plugin** - Use deploy_plugin.sh or manual steps
2. ✅ **Load in AutoCAD** - Tools → Load Application
3. ✅ **Test Connection** - Use nc command or diagnostics
4. ✅ **Verify Events** - Run AutoCAD commands, watch overlay
5. ✅ **Fine-Tune** - Adjust settings if needed
6. ✅ **Test Advanced** - Try subcommands, options, multiple commands

---

## 🆘 Support

### If Setup Works
- Enjoy real-time command overlay!
- See [QUICK_START_PLUGIN.md](QUICK_START_PLUGIN.md) for advanced features

### If Setup Fails
1. Run `./diagnose_connection.sh` for automatic diagnostics
2. Check [PLUGIN_CONNECTION_GUIDE.md](PLUGIN_CONNECTION_GUIDE.md) troubleshooting section
3. Review logs: `log stream --predicate 'process == "TutorCast"' --level debug`
4. Verify network connectivity: `ping 192.168.1.105` and `nc -zv 192.168.1.105 19848`

---

**You're all set! Start with Step 1 and follow the Quick Setup. 🚀**

For detailed info, see the full documentation files linked above.
