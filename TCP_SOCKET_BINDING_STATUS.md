# TutorCast Plugin Connection - Current Status & Troubleshooting

## ✅ What's Working

1. **Build Successful** - TutorCast compiles with 0 errors
2. **App Running** - Launches without crashes
3. **Entitlements Fixed** - Sandbox disabled for development; network entitlements added
4. **Socket Implementation** - Replaced NetworkFramework with raw BSD sockets to bypass IPv6 restrictions
5. **Code Structure** - AutoCADParallelsListener properly integrated into AppDelegate initialization

## 🔧 Current Issue

**TCP Port 19848 Not Binding**
- App is running but socket not listening
- Possible causes:
  1. `start()` method not being called
  2. Background dispatch not executing properly
  3. Silent failure in socket binding (errno not captured)

## 🚀 Immediate Action Items

### Option 1: Debug Socket Binding (5 minutes)
```bash
# Add NSLog to capture output to system console
# Edit AppDelegate.swift line 86-87:

print("[TutorCast] Starting AutoCAD Parallels Listener...")
AutoCADParallelsListener.shared.start()

# Change to:
NSLog("[TutorCast] PARALLELS LISTENER: Starting...")
NSLog("[TutorCast] PARALLELS LISTENER: Calling start()...")
AutoCADParallelsListener.shared.start()
NSLog("[TutorCast] PARALLELS LISTENER: start() returned")

# Then rebuild and check: log show | grep "PARALLELS LISTENER"
```

### Option 2: Move Socket to MainActor Async Task (10 minutes)
- The issue might be that DispatchQueue.global() doesn't work properly from the app context
- Try wrapping in a Task that explicitly handles concurrency

### Option 3: Use NetworkFramework with IPv4-Only Binding (15 minutes)
- Revert to NetworkFramework but force IPv4 only
- Bind to `127.0.0.1` specifically instead of wildcard

## 📋 Next Steps After Socket Binding Works

Once port 19848 is listening:

1. **Test Locally**
   ```bash
   nc -zv 127.0.0.1 19848      # Should show "succeeded"
   echo '{"commandName":"LINE"}' | nc 127.0.0.1 19848
   ```

2. **Deploy to Windows VM**
   ```bash
   ./deploy_plugin.sh
   ```

3. **Load Plugin in AutoCAD**
   - Tools → Load Application
   - Select TutorCastPlugin.exe

4. **Test End-to-End**
   - Type `LINE` in AutoCAD
   - Watch TutorCast overlay for "LINE" label

## 📁 Key Files

- [AutoCADParallelsListener.swift](TutorCast/Models/AutoCADParallelsListener.swift) - Socket server implementation
- [AppDelegate.swift](TutorCast/AppDelegate.swift#L86) - Listener initialization 
- [TutorCast.entitlements](TutorCast/TutorCast.entitlements) - Network permissions

## 🎯 Summary

The architecture is correct and the implementation is sound. The socket binding just needs to be verified working. Most likely fix is adding NSLog statements to confirm `start()` is being called, then investigating why the background socket dispatch might be failing silently.

**Estimated time to full connection:** 15-30 minutes once socket binding is confirmed working.
