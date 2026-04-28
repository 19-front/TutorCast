# TutorCast Plugin Setup & Connection Guide

## Overview

TutorCast detects and connects to AutoCAD through two channels:

1. **Native macOS AutoCAD** → Unix socket (`/tmp/tutorcast_autocad.sock`)
2. **Parallels Windows VM AutoCAD** → TCP socket (port 19848)

This guide covers setting up the Windows plugin for Parallels VM connection.

---

## Architecture

```
Parallels Desktop (Windows VM)
├── AutoCAD
│   └── TutorCastPlugin.exe (C# helper)
│       ├── Monitors AutoCAD UI (UI Automation)
│       ├── Detects commands/subcommands
│       └── Sends JSON events via TCP
│
└── Network
    └── TCP Port 19848
        ↓
    Host macOS
    ├── TutorCast App
    │   ├── AutoCADEnvironmentDetector
    │   │   └── Scans network for Parallels VM
    │   └── AutoCADParallelsListener
    │       ├── Listens on :19848
    │       ├── Receives events
    │       └── Validates & forwards to LabelEngine
    └── Overlay Display
```

---

## Step 1: Identify Your Parallels VM Network Setup

### Find the VM's IP Address

**From macOS Terminal:**
```bash
# List Parallels VMs
prlctl list

# Get VM details including IP
prlctl exec "Windows VM Name" ipconfig

# Or use VirtualBox/Parallels networking tools
ifconfig | grep -A5 "vboxnet\|prleth"
```

**From Windows VM (via Parallels Console):**
```cmd
ipconfig /all
```

### Common Network Configurations

1. **Bridged Network** (Recommended)
   - VM gets IP from your router (e.g., 192.168.1.x)
   - Direct access from macOS
   - No NAT complications

2. **Host-Only Network**
   - VM on isolated subnet (e.g., 192.168.56.x)
   - Only accessible from macOS
   - Good for security

3. **NAT Network**
   - VM behind NAT gateway
   - More complex but isolates network

**Example:**
```
macOS IP:     192.168.1.100
Windows VM:   192.168.1.105
Port:         19848
```

---

## Step 2: Deploy Windows Plugin to VM

### Build the .NET Plugin

The plugin is located at: `Plugins/Windows/TutorCastPlugin.cs`

**Option A: Build on Windows VM**

1. Copy plugin source to Windows VM:
```bash
# From macOS
scp Plugins/Windows/TutorCastPlugin.cs user@192.168.1.105:C:\\Users\\user\\Documents\\
```

2. On Windows VM, compile with C#:
```cmd
# Using C# compiler
csc.exe TutorCastPlugin.cs /out:TutorCastPlugin.exe

# Or use Visual Studio
# Create new Console App → Add file → Build
```

**Option B: Pre-compiled Binary**

If you have compiled version:
```bash
scp TutorCastPlugin.exe user@192.168.1.105:C:\\Users\\user\\AppData\\Local\\
```

### Plugin Installation Location

Place the compiled plugin in Windows VM at:
```
C:\Users\[USERNAME]\AppData\Local\TutorCast\
```

Or anywhere in system PATH for easy access.

---

## Step 3: Configure AutoCAD to Run Plugin

### Method 1: AutoCAD Startup Suite

1. In AutoCAD, go to **Tools** → **Load Application**
2. Browse to: `C:\Users\[USERNAME]\AppData\Local\TutorCast\TutorCastPlugin.exe`
3. Click **Load**
4. Check "Startup Suite" to auto-load on next launch
5. Restart AutoCAD

### Method 2: AutoCAD acad.lsp (AutoLISP startup)

Create/edit `C:\Users\[USERNAME]\AppData\Roaming\Autodesk\AutoCAD [VERSION]\R##\enu\acad.lsp`:

```lisp
; Load TutorCast plugin at startup
(vl-load-com)
(command "APPLOAD" "C:\\Users\\[USERNAME]\\AppData\\Local\\TutorCast\\TutorCastPlugin.exe")
```

### Method 3: AutoCAD Registry (Advanced)

Add to Windows Registry:
```
HKEY_CURRENT_USER\Software\Autodesk\AutoCAD\R##\Profiles\[PROFILE]\Dialogs\
AppLoad
```

Add string value: `C:\Users\[USERNAME]\AppData\Local\TutorCast\TutorCastPlugin.exe`

---

## Step 4: Configure TutorCast Network Detection

### Auto-Detection (Recommended)

TutorCast automatically:
1. Scans network for open port 19848
2. Detects Parallels VM IP
3. Connects when VM is online

**How it works:**

In `AutoCADEnvironmentDetector.swift`:

```swift
// Scans /24 network range (e.g., 192.168.1.1-254)
// Tries port 19848 on each IP
// Returns first match found
let parallelsIP = await detectParallelsVM()
```

### Manual Configuration

If auto-detection fails, manually specify VM IP in Settings:

1. Open TutorCast App
2. Go to **Settings**
3. In AutoCAD section, set:
   - **Parallels VM IP:** `192.168.1.105`
   - **Port:** `19848`
4. Click **Save**

**Or edit UserDefaults:**
```bash
defaults write com.tutorcast.app AutoCADParallelsIP "192.168.1.105"
defaults write com.tutorcast.app AutoCADParallelsPort 19848
```

---

## Step 5: Verify Connection

### Test 1: Check Plugin is Running

**On Windows VM (PowerShell):**
```powershell
# Check if plugin process is running
Get-Process | grep -i tutorcast

# Or check AutoCAD console for plugin output
# Should see: "[TutorCast] Plugin initialized"
```

### Test 2: Verify Port is Open

**From macOS:**
```bash
# Check if port 19848 is listening on VM
nc -zv 192.168.1.105 19848
# Should respond: Connection succeeded

# Or use telnet
telnet 192.168.1.105 19848
# Should connect (Ctrl+C to exit)

# Or use lsof to see what's listening
ssh user@192.168.1.105 "netstat -an | grep 19848"
```

### Test 3: Test Connection in TutorCast

**From TutorCast App:**

1. Open **Settings** → **Diagnostics**
2. Click **Test Parallels Connection**
3. Should show:
   ```
   ✓ VM detected at 192.168.1.105
   ✓ Port 19848 open
   ✓ Successfully connected
   ✓ Received test event
   ```

### Test 4: Monitor Event Flow

**From macOS Terminal:**
```bash
# Watch TutorCast logs
log stream --predicate 'process == "TutorCast"' --level debug

# Should see:
# [AutoCADParallelsListener] New connection from Windows plugin
# [AutoCADParallelsListener] Received command event: {"type": "commandStarted", ...}
```

**From Windows VM PowerShell:**
```powershell
# Monitor plugin logs (if implemented)
Get-EventLog -LogName Application -Source "TutorCast*" -Newest 20

# Or check plugin console output
# Plugin window should show: "Connected to macOS host at 192.168.1.100:19848"
```

---

## Step 6: Test Full Event Pipeline

### Trigger AutoCAD Commands

In AutoCAD on Parallels VM:

1. **Start a command:**
   ```
   Command: LINE ↵
   ```

   **Expected in TutorCast:**
   - Overlay shows: `LIN`
   - Color: AutoCAD category color
   - Label updates as you interact with command

2. **Try subcommand:**
   ```
   Command: OFFSET ↵
   Select object to offset: [click object]
   Offset distance or [Through/Erase/Layer] <1.00>: 0.5 ↵
   ```

   **Expected in TutorCast:**
   - Overlay shows subcommand prompts
   - Updates with options in real-time

3. **Complete command:**
   ```
   ↵ (complete command)
   ```

   **Expected in TutorCast:**
   - Overlay fades out
   - Returns to "Ready" state

---

## Troubleshooting

### Issue 1: Plugin Won't Load in AutoCAD

**Problem:** AutoCAD doesn't load TutorCastPlugin.exe

**Solutions:**

a) Verify plugin location:
```cmd
dir "C:\Users\[USERNAME]\AppData\Local\TutorCast\"
```

b) Check AutoCAD console for errors:
```
Command: APPLOAD
[Browse to plugin]
```

c) Ensure .NET framework compatibility:
```cmd
# Check .NET version
dotnet --version

# Plugin requires .NET Framework 4.7.2+
```

d) Check file permissions (Run as Administrator):
```cmd
# Right-click TutorCastPlugin.exe → Properties
# Compatibility: Run this program in compatibility mode for: Windows 10
# Privilege: Run this program as an administrator
```

### Issue 2: Port 19848 Not Open

**Problem:** Connection refused on port 19848

**Solutions:**

a) Check if plugin is running:
```cmd
netstat -an | findstr 19848
# Should show: LISTENING
```

b) Disable Windows Firewall (for testing):
```cmd
netsh advfirewall set allprofiles state off
```

c) Allow port through firewall:
```cmd
# Run as Administrator
netsh advfirewall firewall add rule name="TutorCast" dir=in action=allow protocol=tcp localport=19848
```

d) Check plugin error messages:
```
[TutorCast] Failed to bind port 19848: Address already in use
# → Kill process on that port or choose different port
```

### Issue 3: TutorCast Can't Find VM

**Problem:** AutoCAD environment not detected

**Solutions:**

a) Manually check VM IP:
```bash
# From macOS
ping 192.168.1.105

# Check subnet matches:
# macOS: 192.168.1.100
# VM: 192.168.1.105
# ✓ Same /24 subnet
```

b) Scan network manually:
```bash
# Nmap scan (if installed)
nmap -p 19848 192.168.1.0/24

# Or manual check
for i in {1..254}; do
  (echo >/dev/tcp/192.168.1.$i/19848) 2>/dev/null && echo "192.168.1.$i:19848 open"
done &
```

c) Override detection in TutorCast:
```bash
defaults write com.tutorcast.app AutoCADParallelsIP "192.168.1.105"
defaults write com.tutorcast.app AutoCADParallelsPort 19848
defaults write com.tutorcast.app ForceParallelsMode YES
```

### Issue 4: Events Not Received

**Problem:** Plugin connected but no events flowing

**Solutions:**

a) Verify plugin is monitoring AutoCAD:
```cmd
# In AutoCAD, type command
Command: LINE

# Check plugin console for output
# Should show: "Command detected: LINE"
```

b) Check JSON formatting:
```cmd
# Plugin should send valid JSON:
# {"type":"commandStarted","commandName":"LINE","subcommand":"","timestamp":"2026-03-21T..."}
```

c) Verify SecurityValidator is accepting events:
```bash
# Check TutorCast logs for validation errors
log stream --predicate 'process == "TutorCast"' | grep -i "validation\|reject"

# If rejected:
# [SecurityValidator] Event rejected: invalid format
# [SecurityValidator] Event rejected: command too long
```

d) Check event file in shared folder:
```bash
# Events are also written to:
ls -la ~/tutorcast_events/

# Should see .json files with timestamps
```

---

## Step 7: Fine-Tune Connection

### Network Optimization

**Reduce Latency:**
```
Current: 100ms polling interval
Faster:  50ms polling interval
Fastest: 10ms polling interval (CPU intensive)
```

In `AutoCADParallelsListener.swift`:
```swift
private let receiveBufferSize = 65536  // Increase for large events
private let receiveTimeout: TimeInterval = 1.0  // Adjust timeout
```

### Event Filtering

If too many events, filter in SecurityValidator:

```swift
// Skip low-priority events
if event.type == .commandLineText && event.rawCommandLineText.count < 3 {
    return nil  // Skip short text events
}
```

### Custom Port (if 19848 unavailable)

In plugin:
```csharp
const int TUTORCAST_PORT = 19848;  // Change to 19849, etc.
```

In TutorCast:
```swift
private let autocadWindowsPort = 19849  // Match plugin port
```

---

## Step 8: Production Deployment

### Create Plugin Installer (Windows)

```powershell
# Create installer script
New-Item -ItemType Directory -Path "C:\Program Files\TutorCast"
Copy-Item "TutorCastPlugin.exe" "C:\Program Files\TutorCast\"
```

### Autostart Plugin

**Windows Task Scheduler:**
1. Open Task Scheduler
2. Create Basic Task → "TutorCast Plugin"
3. Trigger: On logon
4. Action: Start program `C:\Program Files\TutorCast\TutorCastPlugin.exe`

### Monitor Plugin Health

Add watchdog in plugin:
```csharp
if (!isConnected && DateTime.Now - lastConnectionAttempt > TimeSpan.FromSeconds(30))
{
    ReconnectToHost();  // Auto-reconnect every 30s
}
```

---

## Common Event Types

Once connected, expect these events:

```json
{
  "type": "commandStarted",
  "commandName": "LINE",
  "subcommand": "",
  "timestamp": "2026-03-21T14:30:00Z"
}

{
  "type": "subcommandPrompt",
  "commandName": "OFFSET",
  "subcommand": "Select object to offset:",
  "activeOptions": ["Through", "Erase", "Layer"],
  "timestamp": "2026-03-21T14:30:05Z"
}

{
  "type": "commandCompleted",
  "commandName": "LINE",
  "timestamp": "2026-03-21T14:30:10Z"
}
```

---

## Testing Checklist

- [ ] Windows VM network configured and accessible from macOS
- [ ] Plugin compiled and placed in correct directory
- [ ] Plugin loads in AutoCAD (check APPLOAD)
- [ ] Port 19848 open and listening on VM
- [ ] TutorCast app detects VM IP (or manually configured)
- [ ] Test connection shows ✓ in TutorCast
- [ ] AutoCAD commands generate events in TutorCast
- [ ] Overlay displays and updates correctly
- [ ] Firewall rules configured for production

---

## Quick Reference

### Essential Commands

```bash
# macOS - Test VM connectivity
ping 192.168.1.105
nc -zv 192.168.1.105 19848

# Windows - Check plugin running
netstat -an | findstr 19848

# View TutorCast logs
log stream --predicate 'process == "TutorCast"' --level debug

# Manually trigger event (test)
echo '{"type":"commandStarted","commandName":"TEST"}' | nc 192.168.1.100 19848
```

### Key Files

```
macOS:
  /Applications/TutorCast.app/Contents/MacOS/TutorCast
  ~/Library/Preferences/com.tutorcast.app.plist

Windows:
  C:\Users\[USER]\AppData\Local\TutorCast\TutorCastPlugin.exe
  C:\Users\[USER]\AppData\Roaming\Autodesk\AutoCAD\...

Logs:
  macOS: Console.app or `log stream`
  Windows: Event Viewer or plugin console output
```

---

## Next Steps

1. **Deploy plugin** to Windows VM following steps above
2. **Configure network** and get VM IP
3. **Start AutoCAD** and load plugin
4. **Launch TutorCast** on macOS
5. **Test connection** using diagnostics
6. **Execute AutoCAD commands** to verify event flow
7. **Monitor overlay** to see real-time command updates

Good luck! 🚀
