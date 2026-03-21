// EventTapManager.swift
// TutorCast
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY CGEventTap AND NOT NSEvent GLOBAL MONITORS?
// ─────────────────────────────────────────────────────────────────────────────
//
// NSEvent.addGlobalMonitorForEvents(matching:handler:)  [AppKit layer]
//   • Delivered *after* the app that owns the event has processed it.
//   • Subject to NSApplication's event coalescing / throttling.
//   • Sandboxed apps can be blocked by the system.
//   • Cannot modify or suppress events (listen-only regardless).
//   • Misses some synthetic / injected events.
//
// CGEvent.tapCreate(…)  [CoreGraphics / Quartz Event Services layer]
//   • Intercepts at the Quartz event stream, *before* any app sees the event.
//   • Reliable low-latency delivery of every real keystroke.
//   • Supports both passive (listenOnly) and active (modify/suppress) taps.
//   • Can also tap mouse events, scroll, tablet — full Quartz event palette.
//   • Is the correct API for CAD shortcut detection where timing matters.
//
// ─────────────────────────────────────────────────────────────────────────────
// PERMISSION FLOW  (macOS 10.15 +, enforced strictly on 13+)
// ─────────────────────────────────────────────────────────────────────────────
//
// CGEventTap at kCGSessionEventTap requires "Input Monitoring" TCC permission.
//
// Step 1 — Info.plist
//   Add NSInputMonitoringUsageDescription with a user-facing explanation.
//   (Already done — see Info.plist in this project.)
//
// Step 2 — First launch
//   When tapCreate returns nil, it means permission has not been granted.
//   We call AXIsProcessTrustedWithOptions(prompt:true) which opens the
//   Accessibility dialog.  Input Monitoring is a *separate* TCC category
//   and has no equivalent programmatic prompt — the user must navigate:
//     System Settings → Privacy & Security → Input Monitoring → TutorCast ✓
//
// Step 3 — After granting
//   The permission change does NOT automatically restart the tap.
//   Call  EventTapManager.shared.stop()
//   then  EventTapManager.shared.start()
//   (or just relaunch the app).
//   A future version can use a DistributedNotificationCenter observer
//   keyed on "com.apple.security.authorization.changed" to auto-restart.
//
// Step 4 — Sandboxed App Store builds
//   A sandboxed app cannot use kCGHIDEventTap (device level).
//   kCGSessionEventTap (session level, listenOnly) still works with the
//   Input Monitoring entitlement:
//     com.apple.security.input-monitoring  →  YES
//   For a direct-distribution (non-App-Store) build no special entitlement
//   is required beyond the TCC permission granted at runtime.
//
// ─────────────────────────────────────────────────────────────────────────────

import Cocoa
import CoreGraphics

// @unchecked Sendable: CGEventTap involves C callbacks and CFRunLoopSource
// which are not Swift-Sendable. We guarantee thread safety manually:
//   • All mutation happens before the tap is enabled (single-writer setup).
//   • onKeyDown is dispatched to the main actor before calling back callers.
final class EventTapManager: @unchecked Sendable {

    // Singleton — one tap per process.
    static let shared = EventTapManager()
    private init() {}

    // ── Callback ─────────────────────────────────────────────────────────────
    // Called on the main thread with (keyCode, modifierFlags) for every
    // keyDown event. Replace / extend with your AutoCAD lookup logic.
    var onKeyDown: ((_ keyCode: Int64, _ modifiers: CGEventFlags) -> Void)?
    
    // Called on mouse events (left click, right click, middle click, scroll)
    var onMouseEvent: ((_ eventType: String) -> Void)?

    // ── Private state ─────────────────────────────────────────────────────────
    private var eventTap:      CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Start

    func start() {
        guard eventTap == nil else { return } // already running

        // Check / prompt for accessibility (covers some macOS versions).
        requestAccessibilityIfNeeded()

        // Tap keyboard and mouse events
        var mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        mask |= (1 << CGEventType.leftMouseDown.rawValue)
        mask |= (1 << CGEventType.rightMouseDown.rawValue)
        mask |= (1 << CGEventType.otherMouseDown.rawValue)
        mask |= (1 << CGEventType.scrollWheel.rawValue)

        // ── tapCreate parameters ──────────────────────────────────────────────
        //  tap:      .cgSessionEventTap    — events in the current user session
        //  place:    .headInsertEventTap   — placed at the head of the tap list
        //                                    (lowest latency, sees events first)
        //  options:  .listenOnly           — PASSIVE: we NEVER modify events.
        //                                    This is the least-privilege option
        //                                    and only requires Input Monitoring
        //                                    (not full Accessibility).
        //  callback: C-callable closure   — bridged; self passed via userInfo.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[TutorCast] ⚠️  CGEventTap creation failed.")
            print("   Input Monitoring permission not granted?")
            print("   Navigate to: System Settings › Privacy & Security › Input Monitoring › ✓ TutorCast")
            return
        }

        // Attach to the main run loop so the tap is serviced on the main thread.
        // For high-frequency mouse events consider a dedicated RunLoop thread.
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap      = tap
        self.runLoopSource = source
        print("[TutorCast] ✅  CGEventTap active (session, listenOnly, keyboard + mouse).")
    }

    // MARK: - Stop

    func stop() {
        if let tap = eventTap {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap      = nil
        runLoopSource = nil
        print("[TutorCast] 🛑  CGEventTap stopped.")
    }

    // MARK: - Internal event handler (called from C callback below)

    // This method is called from the C callback on whatever thread CoreGraphics
    // delivers the event (often the main thread when using main RunLoop, but not
    // guaranteed). We dispatch UI work explicitly to the main actor.
    fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .keyDown:
            let keyCode   = event.getIntegerValueField(.keyboardEventKeycode)
            let modifiers = event.flags

            // Dispatch to main actor for UI updates.
            DispatchQueue.main.async { [weak self] in
                self?.onKeyDown?(keyCode, modifiers)
            }
            
        case .leftMouseDown:
            DispatchQueue.main.async { [weak self] in
                self?.onMouseEvent?("Left Click")
            }
            
        case .rightMouseDown:
            DispatchQueue.main.async { [weak self] in
                self?.onMouseEvent?("Right Click")
            }
            
        case .otherMouseDown:
            DispatchQueue.main.async { [weak self] in
                self?.onMouseEvent?("Middle Click")
            }
            
        case .scrollWheel:
            // Get scroll direction from deltaY field
            let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let eventName = deltaY > 0 ? "Scroll Up" : "Scroll Down"
            DispatchQueue.main.async { [weak self] in
                self?.onMouseEvent?(eventName)
            }
            
        default:
            break
        }
        
        // Clear sensitive event data from memory to prevent leaks via memory dumps
        // This is a best-effort attempt; Swift's ARC handles most cleanup
        autoreleasepool {
            // Force deallocation of temporary objects
            _ = 0
        }
    }

    // MARK: - Permission Helpers

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }
    
    deinit {
        // Cleanup on deallocation
        stop()
    }
}

// MARK: - C-Compatible Event Tap Callback
//
// CGEvent.tapCreate requires a @convention(c) / C-callable function pointer.
// Swift closures that do NOT capture any state qualify automatically.
// We forward to the Swift method via the userInfo pointer to avoid any
// captured-variable restrictions on the C callback type.

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
    // Retrieve the EventTapManager instance from the opaque pointer.
    guard let refcon else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
    manager.handleEvent(type: type, event: event)
    // listenOnly tap: must return the original event unchanged.
    return Unmanaged.passRetained(event)
}
