# START HERE - TutorCast Plugin Setup

## Your Next Steps (Choose Your Path)

### 5-Minute Setup (Recommended First)
**Read This:** QUICK_START_PLUGIN.md

Quick overview + minimal steps to get connected:
- Identify VM IP
- Deploy plugin
- Load in AutoCAD
- Test connection

### Detailed Setup (If You Get Stuck)
**Read This:** PLUGIN_CONNECTION_GUIDE.md

Comprehensive guide with:
- Step-by-step instructions
- Network troubleshooting
- AutoCAD configuration options
- Production deployment

### Troubleshooting & Diagnostics
**Run This:** `./diagnose_connection.sh`

Automatic diagnostic tool checks:
- TutorCast app status
- VM IP configuration
- Network connectivity
- Port listening status
- Plugin installation
- Recent log events

### Automated Deployment
**Run This:** `./deploy_plugin.sh`

Semi-automated setup (guided prompts):
- Detects Parallels VMs
- Copies plugin to Windows
- Configures TutorCast
- Tests connection

---

## Quick Start Commands

```bash
# 1. Get your VM IP
prlctl exec Windows ipconfig | grep IPv4

# 2. Run diagnostics
./diagnose_connection.sh

# 3. Deploy plugin
./deploy_plugin.sh
```

---

## What You're Setting Up

```
Windows VM (Parallels)     TCP/19848     macOS (TutorCast)
├─ AutoCAD                 ────────────  ├─ TutorCast App
├─ Plugin                  JSON Events   ├─ Listener
                                         └─ Overlay Display
```

---

## Success Checklist

When working correctly:
- [ ] TutorCast running on macOS
- [ ] Plugin loaded in AutoCAD on Windows
- [ ] Type AutoCAD command (e.g., LINE)
- [ ] TutorCast overlay shows command name
- [ ] Overlay updates as you interact with command
- [ ] Clears when command completes

---

## Available Documentation

- SETUP_COMPLETE.md - Full overview
- EVENT_FORMAT_REFERENCE.md - API reference
- PLUGIN_CONNECTION_GUIDE.md - Detailed guide
- QUICK_START_PLUGIN.md - Quick start

---

**Pick one of the paths above and get started!**
