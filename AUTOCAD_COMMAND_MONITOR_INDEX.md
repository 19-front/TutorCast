# AutoCAD Command Monitor Feature - Documentation Index

## Overview

This document provides a roadmap to all files and documentation related to the AutoCAD Command Monitor feature implementation.

---

## 📁 Source Code Files

### Core Implementation (New Files)

| File | Lines | Purpose |
|------|-------|---------|
| [AutoCADCommandMonitor.swift](../TutorCast/AutoCADCommandMonitor.swift) | 150 | Main orchestrator for command monitoring with environment detection |
| [NativeMacOSAutoCADReader.swift](../TutorCast/NativeMacOSAutoCADReader.swift) | 380 | Accessibility API implementation for reading native macOS AutoCAD |
| [ParallelsWindowsAutoCADReader.swift](../TutorCast/ParallelsWindowsAutoCADReader.swift) | 290 | Socket-based IPC for Windows VM in Parallels Desktop |

### Updated Files

| File | Changes | Details |
|------|---------|---------|
| [LabelEngine.swift](../TutorCast/Models/LabelEngine.swift) | +50 lines | Added command display support, dual-mode reactivity |
| [OverlayContentView.swift](../TutorCast/OverlayContentView.swift) | +85 lines | Dual-line layout, command color scheme, responsive typography |
| [AppDelegate.swift](../TutorCast/AppDelegate.swift) | +6 lines | AutoCADCommandMonitor lifecycle management |
| [TutorCast.entitlements](../TutorCast/TutorCast.entitlements) | +1 line | Accessibility API entitlement |
| [Info.plist](../TutorCast/Info.plist) | +8 lines | Enhanced Accessibility usage description |

---

## 📚 Documentation Files

### Getting Started

**[AUTOCAD_COMMAND_MONITOR_QUICK_START.md](./AUTOCAD_COMMAND_MONITOR_QUICK_START.md)** ⭐ START HERE
- Build and test instructions
- Permission grant walkthrough
- Test cases (5 scenarios)
- Console debugging guide
- Troubleshooting checklist
- **Best for:** Developers who want to build and test immediately

### Feature Architecture & Design

**[AUTOCAD_COMMAND_MONITOR_FEATURE.md](./AUTOCAD_COMMAND_MONITOR_FEATURE.md)** 📖 COMPREHENSIVE GUIDE
- Complete feature overview
- Architecture diagrams and flow
- Detailed implementation explanations
  - AutoCADCommandMonitor orchestrator
  - NativeMacOSAutoCADReader (AX API)
  - ParallelsWindowsAutoCADReader (socket IPC)
  - LabelEngine dual-mode updates
  - OverlayContentView layout
- Usage examples and API reference
- Permissions and security model
- Error handling strategies
- Performance metrics
- Testing checklist
- Future enhancement roadmap
- **Best for:** Understanding the full design and implementation details

### Implementation Complete Report

**[AUTOCAD_COMMAND_MONITOR_IMPLEMENTATION_COMPLETE.md](./AUTOCAD_COMMAND_MONITOR_IMPLEMENTATION_COMPLETE.md)** ✅ STATUS REPORT
- What was built (component breakdown)
- Key features implemented
- Architecture overview
- What works now (native macOS)
- What's pending (Windows helper)
- User permissions required
- Testing instructions
- Performance metrics
- Files modified summary
- Success criteria checklist
- **Best for:** Project status and overview of deliverables

### Windows Helper Implementation

**[WINDOWS_HELPER_IMPLEMENTATION.md](./WINDOWS_HELPER_IMPLEMENTATION.md)** 🪟 WINDOWS DEVELOPER GUIDE
- Complete C# implementation guide
- Architecture and requirements
- Socket protocol specification
- UI Automation (UIA) integration
- Build and deployment instructions
- Error handling and troubleshooting
- Testing procedures
- **Best for:** Windows developers implementing TutorCastHelper.exe

---

## 🔍 Quick Reference

### For Different Roles

#### **QA / Testers**
1. Start with: [AUTOCAD_COMMAND_MONITOR_QUICK_START.md](./AUTOCAD_COMMAND_MONITOR_QUICK_START.md)
2. Follow build & test steps
3. Execute test scenarios 1-5
4. Report results

#### **iOS/macOS Developers**
1. Read: [AUTOCAD_COMMAND_MONITOR_FEATURE.md](./AUTOCAD_COMMAND_MONITOR_FEATURE.md) — Architecture section
2. Review: [AutoCADCommandMonitor.swift](../TutorCast/AutoCADCommandMonitor.swift)
3. Review: [NativeMacOSAutoCADReader.swift](../TutorCast/NativeMacOSAutoCADReader.swift)
4. Study: Accessibility API calls and error handling

#### **Windows/.NET Developers**
1. Read: [WINDOWS_HELPER_IMPLEMENTATION.md](./WINDOWS_HELPER_IMPLEMENTATION.md) — Complete section
2. Reference: Socket protocol in ParallelsWindowsAutoCADReader
3. Implement: TutorCastHelper.exe using provided C# templates

#### **Project Managers / Tech Leads**
1. Review: [AUTOCAD_COMMAND_MONITOR_IMPLEMENTATION_COMPLETE.md](./AUTOCAD_COMMAND_MONITOR_IMPLEMENTATION_COMPLETE.md)
2. Check: Success Criteria Met section
3. Review: Performance Metrics and Testing Instructions

#### **Documentation / UX Writers**
1. Read: [AUTOCAD_COMMAND_MONITOR_FEATURE.md](./AUTOCAD_COMMAND_MONITOR_FEATURE.md) — Usage section
2. Review: User Permissions section
3. Check: Info.plist descriptions for user-facing text

---

## 🏗️ Architecture Diagrams

### Component Relationship
```
┌─────────────────────────────────────────────────────┐
│           OverlayContentView                         │
│           (Renders dual-line display)               │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
        ┌──────────────────────┐
        │    LabelEngine       │
        │ (Command + Event)    │
        └──┬──────────────┬────┘
           │              │
           ▼              ▼
      EventTap      AutoCADCommandMonitor
      (keyboard)    (direct read)
           │              │
           │      ┌───────┴────────┐
           │      ▼                ▼
           │   Native Reader   Parallels Reader
           │   (Accessibility) (Socket IPC)
           │      │                │
           └─────►├────────┬───────┘
                  │        │
                  ▼        ▼
              AutoCAD   Windows VM
              (macOS)   (Parallels)
```

### Command Data Flow
```
AutoCAD Command State
        ↓
   [Reader detects]
        ↓
   Parse & extract
   - commandName
   - subcommandText
        ↓
   AutoCADCommandMonitor
   (@Published properties)
        ↓
   LabelEngine
   (@Published properties)
        ↓
   OverlayContentView
   (render dual-line)
```

---

## 📊 Code Statistics

```
Total New Code:        ~920 lines (3 new files)
Total Modified Code:   ~150 lines (5 files)
Total Documentation:   ~1200 lines (4 markdown files)
────────────────────────────────────────
TOTAL:                 ~2270 lines
```

---

## 🔑 Key Concepts

### Environment Detection
- **Native macOS:** Uses Accessibility API (AXUIElement)
- **Parallels Windows:** Uses TCP socket to helper (127.0.0.1:24680)
- **Fallback:** Keyboard-only mode if neither detected

### Display Modes
1. **Event Mode:** Shows keyboard shortcut label
   - "Z+" (zoom in), "Pn/Pan" (pan), etc.
   
2. **Command Mode:** Shows AutoCAD command + prompt
   - Primary: Command name (large, cyan)
   - Secondary: Subcommand/prompt (smaller, dimmed)

### Polling & Caching
- Poll interval: 100ms (10 Hz)
- Element cache TTL: 5 seconds
- Socket timeout: 2 seconds

### Permissions
1. **Input Monitoring** — For CGEventTap keyboard capture
2. **Accessibility** — For AXUIElement access (native only)

---

## ✅ Success Criteria

All implemented and complete:
- ✅ Reads active AutoCAD command directly
- ✅ Reads active subcommand/prompt
- ✅ Displays both on overlay (large command, small prompt)
- ✅ Detects environment automatically (native vs Parallels)
- ✅ Bypasses keyboard inference
- ✅ Full semantic context in display
- ✅ Graceful fallback if not available
- ✅ Comprehensive documentation

---

## 🚀 What's Next

### Ready to Test
- ✅ Native macOS AutoCAD integration
- ✅ Overlay dual-line display
- ✅ Permission flows

### Needs Implementation
- 🔴 Windows helper (TutorCastHelper.exe)
  - See: [WINDOWS_HELPER_IMPLEMENTATION.md](./WINDOWS_HELPER_IMPLEMENTATION.md)

### Future Enhancements
- [ ] Command option parsing
- [ ] Keyboard hint overlays
- [ ] Command history display
- [ ] Auto-launch Parallels helper
- [ ] Multi-monitor optimization

---

## 📞 Support & Troubleshooting

### Quick Answers
| Question | Answer |
|----------|--------|
| Where do I start? | [AUTOCAD_COMMAND_MONITOR_QUICK_START.md](./AUTOCAD_COMMAND_MONITOR_QUICK_START.md) |
| How does it work? | [AUTOCAD_COMMAND_MONITOR_FEATURE.md](./AUTOCAD_COMMAND_MONITOR_FEATURE.md) |
| What was built? | [AUTOCAD_COMMAND_MONITOR_IMPLEMENTATION_COMPLETE.md](./AUTOCAD_COMMAND_MONITOR_IMPLEMENTATION_COMPLETE.md) |
| How to implement Windows helper? | [WINDOWS_HELPER_IMPLEMENTATION.md](./WINDOWS_HELPER_IMPLEMENTATION.md) |
| Getting permission errors? | See QUICK_START.md Common Issues section |

### Console Commands

```bash
# View TutorCast logs
log stream --process=TutorCast 2>&1 | grep -E "AutoCAD|Error|permission"

# Check if AutoCAD is running
ps aux | grep -i autocad

# Verify socket listening (after Windows helper)
nc -zv 127.0.0.1 24680
```

---

## 📝 Document Navigation

```
📖 Reading Guide:
1. Start: QUICK_START.md (5 min read)
   ↓
2. Deep Dive: FEATURE.md (30 min read)
   ↓
3. Implementation: IMPLEMENTATION_COMPLETE.md (10 min read)
   ↓
4. Windows Dev: WINDOWS_HELPER.md (for Windows devs only)
```

---

## 🏆 Implementation Status

| Component | Status | Files |
|-----------|--------|-------|
| Core Monitor | ✅ Complete | AutoCADCommandMonitor.swift |
| Native Reader | ✅ Complete | NativeMacOSAutoCADReader.swift |
| Parallels Reader | ✅ Complete* | ParallelsWindowsAutoCADReader.swift |
| LabelEngine | ✅ Complete | LabelEngine.swift (modified) |
| Overlay | ✅ Complete | OverlayContentView.swift (modified) |
| AppDelegate | ✅ Complete | AppDelegate.swift (modified) |
| Permissions | ✅ Complete | .entitlements, Info.plist |
| Documentation | ✅ Complete | 4 markdown files |
| **Windows Helper** | ⏳ Guide Only | WINDOWS_HELPER_IMPLEMENTATION.md |

*Parallels reader implemented, helper not yet implemented

---

**Last Updated:** March 2026  
**Feature Status:** 🟢 Ready for Testing (macOS), ⏳ Pending Windows Helper  
**Documentation Status:** 🟢 Complete

---

## Quick Links

- 🔗 [Build & Test Guide](./AUTOCAD_COMMAND_MONITOR_QUICK_START.md)
- 🔗 [Architecture & Design](./AUTOCAD_COMMAND_MONITOR_FEATURE.md)
- 🔗 [Implementation Status](./AUTOCAD_COMMAND_MONITOR_IMPLEMENTATION_COMPLETE.md)
- 🔗 [Windows Helper Guide](./WINDOWS_HELPER_IMPLEMENTATION.md)
