// AppDelegate.swift
// TutorCast
//
// Responsibilities:
//   1. Set activation policy to .accessory → hides Dock icon (menu-bar app).
//   2. Instantiate and expose OverlayWindowController so TutorCastApp can
//      pass it into the SwiftUI environment.
//   3. Start the CGEventTap and wire up the key-down callback.
//   4. Show the overlay on first launch.

import AppKit
import Combine

// @MainActor: All AppDelegate callbacks are on the main thread; making the
// class MainActor-isolated keeps Swift 6 strict-concurrency happy without
// littering individual methods with nonisolated overrides.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    // Shared overlay controller. Exposed so TutorCastApp can inject it
    // into the SwiftUI environment via .environmentObject().
    let overlayController = OverlayWindowController()

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {

        // ── Hide Dock icon ──────────────────────────────────────────────────
        // .accessory = no Dock tile, no App Switcher entry.
        // Must be set before any window is shown.
        NSApp.setActivationPolicy(.accessory)

        // ── Initialize Label Engine ─────────────────────────────────────────
        // This sets up event monitoring and profile binding
        let _ = LabelEngine.shared
        
        // ── Run Environment Detection and Wire Up Listeners ────────────────
        // Detect if native macOS or Parallels Windows AutoCAD is running,
        // then start the appropriate listener and wire its events to LabelEngine.
        Task {
            let env = await AutoCADEnvironmentDetector.shared.detect()
            
            switch env {
            case .nativeMac:
                print("[TutorCast] AutoCAD native macOS detected, starting Unix socket listener...")
                AutoCADNativeListener.shared.onEvent = { event in
                    LabelEngine.shared.processCommandEvent(event)
                }
                AutoCADNativeListener.shared.start()
                
            case .parallelsWindows(let vmIP):
                print("[TutorCast] AutoCAD Parallels Windows detected at \(vmIP), starting TCP listener...")
                AutoCADParallelsListener.shared.onEvent = { event in
                    LabelEngine.shared.processCommandEvent(event)
                }
                AutoCADParallelsListener.shared.start(vmIP: vmIP)
                
            case .notRunning, .unknown:
                print("[TutorCast] AutoCAD not detected. Keyboard inference mode active.")
                break
            }
        }
        
        // ── Re-run Detection When Apps Launch ────────────────────────────
        // When a new application launches (e.g., user starts AutoCAD),
        // re-run detection to potentially start the listener.
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { 
                let env = await AutoCADEnvironmentDetector.shared.detect()
                if case .nativeMac = env {
                    if !AutoCADNativeListener.shared.isRunning {
                        print("[TutorCast] AutoCAD native macOS launched, starting listener...")
                        AutoCADNativeListener.shared.start()
                    }
                } else if case .parallelsWindows(let vmIP) = env {
                    if !AutoCADParallelsListener.shared.isRunning {
                        print("[TutorCast] AutoCAD Parallels launched, starting listener...")
                        AutoCADParallelsListener.shared.start(vmIP: vmIP)
                    }
                }
            }
        }

        // ── CGEventTap ──────────────────────────────────────────────────────
        // Start monitoring keyboard events. Will prompt for permissions if
        // Input Monitoring has not been granted yet (see EventTapManager for
        // the full permission-flow commentary).
        EventTapManager.shared.start()

        // Wire up the key-down handler.
        // Convert key codes to event strings and feed to KeyMouseMonitor
        // so that LabelEngine can map them to AutoCAD commands.
        EventTapManager.shared.onKeyDown = { [weak self] keyCode, modifiers in
            guard let self else { return }
            
            // Convert key code to human-readable key name and build modifier string
            if let keyName = self.keyNameForCode(keyCode) {
                let eventString = self.buildEventString(keyName: keyName, modifiers: modifiers)
                print("[TutorCast] Key mapped: code=\(keyCode) → '\(eventString)'")
                KeyMouseMonitor.shared.simulate(event: eventString)
            } else {
                print("[TutorCast] keyDown  code=\(keyCode)  mods=\(modifiers) [UNMAPPED]")
            }
        }
        
        // Wire up the mouse event handler
        // Forward mouse clicks and scrolls directly to KeyMouseMonitor
        EventTapManager.shared.onMouseEvent = { eventType in
            print("[TutorCast] Mouse event: '\(eventType)'")
            KeyMouseMonitor.shared.simulate(event: eventType)
        }
        
        // ── Register Global Hotkey ───────────────────────────────────────────
        // ⌃⌥⌘K toggles the overlay visibility
        KeyboardShortcutManager.shared.registerToggleOverlayHotkey { [weak self] in
            self?.overlayController.toggleOverlay()
            print("[TutorCast] Overlay toggled via ⌃⌥⌘K")
        }

        // ── Setup Menu Bar ─────────────────────────────────────────────────
        setupMenuBar()

        // ── Show overlay ────────────────────────────────────────────────────
        overlayController.showOverlay()
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // Application menu
        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(title: "About TutorCast", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = NSApp
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())
        
        // Settings menu item
        appMenu.addItem(
            withTitle: "Settings",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit TutorCast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Profiles menu
        let profilesMenu = NSMenu(title: "Profiles")
        
        let settingsStore = SettingsStore.shared
        for (_, profile) in settingsStore.profiles.enumerated() {
            let isActive = settingsStore.activeProfileID == profile.id.uuidString
            let checkmark = isActive ? "✓ " : "  "
            let menuItem = NSMenuItem(
                title: "\(checkmark)\(profile.name)",
                action: #selector(switchProfile(_:)),
                keyEquivalent: ""
            )
            menuItem.representedObject = profile.id
            menuItem.state = isActive ? .on : .off
            profilesMenu.addItem(menuItem)
        }
        
        profilesMenu.addItem(NSMenuItem.separator())
        profilesMenu.addItem(
            withTitle: "Manage Profiles…",
            action: #selector(showProfiles),
            keyEquivalent: ""
        )

        let profilesMenuItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        profilesMenuItem.submenu = profilesMenu
        mainMenu.addItem(profilesMenuItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(
            withTitle: "Toggle Overlay",
            action: #selector(toggleOverlay),
            keyEquivalent: "k"
        )
        viewMenu.item(at: 0)?.keyEquivalentModifierMask = [.control, .option, .command]

        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func switchProfile(_ sender: NSMenuItem) {
        guard let profileID = sender.representedObject as? UUID else { return }
        if let profile = SettingsStore.shared.profiles.first(where: { $0.id == profileID }) {
            SettingsStore.shared.setActiveProfile(profile)
            print("[TutorCast] Switched to profile: \(profile.name)")
            // Rebuild menu to update checkmarks
            setupMenuBar()
        }
    }

    @objc private func toggleOverlay() {
        overlayController.toggleOverlay()
    }

    @objc private func showSettings() {
        // Create and show settings window
        let controller = SettingsWindowController(store: SettingsStore.shared)
        controller.show()
    }

    @objc private func showProfiles() {
        showSettings()
    }

    // MARK: - Key Code Mapping

    /// Build an event string from key name and modifiers (e.g., "Ctrl+D", "Shift+S")
    private func buildEventString(keyName: String, modifiers: CGEventFlags) -> String {
        var parts: [String] = []
        
        // Check modifiers in order: Ctrl, Alt/Option, Shift, Cmd
        if modifiers.contains(.maskControl) {
            parts.append("Ctrl")
        }
        if modifiers.contains(.maskAlternate) {
            parts.append("Alt")
        }
        if modifiers.contains(.maskShift) {
            parts.append("Shift")
        }
        if modifiers.contains(.maskCommand) {
            parts.append("Cmd")
        }
        
        // Add the key name
        parts.append(keyName)
        
        // Join with + if there are modifiers, otherwise just return the key
        return parts.joined(separator: "+")
    }

    /// Convert macOS key codes to human-readable key names for display.
    /// Based on standard US ANSI keyboard layout.
    private func keyNameForCode(_ code: Int64) -> String? {
        switch code {
        // Row 1: Numbers and symbols
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        case 27: return "-"
        case 24: return "="
        
        // Row 2: QWERTY row
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 17: return "T"
        case 16: return "Y"
        case 32: return "U"
        case 34: return "I"
        case 31: return "O"
        case 35: return "P"
        case 33: return "["
        case 30: return "]"
        case 42: return "\\"
        
        // Row 3: ASDF row
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 41: return ";"
        case 39: return "'"
        case 36: return "Return"
        
        // Row 4: ZXCV row
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 45: return "N"
        case 46: return "M"
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        
        // Special keys
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 52: return "Enter"
        case 53: return "Esc"
        
        // Function keys
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        
        // Arrow keys
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        
        // Modifier-only events (should typically be ignored but included for completeness)
        case 55: return "Cmd"
        case 56: return "Shift"
        case 58: return "Alt"
        case 59: return "Ctrl"
        
        // Navigation keys
        case 114: return "Ins"
        case 115: return "Home"
        case 116: return "PgUp"
        case 117: return "Del"
        case 119: return "End"
        case 121: return "PgDn"
        
        default: return nil
        }
    }

    // MARK: - Termination

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up global hotkey
        KeyboardShortcutManager.shared.unregisterHotkey()
        // Stop AutoCAD environment detection
        AutoCADEnvironmentDetector.shared.stopDetection()
        // Stop AutoCAD native listener
        AutoCADNativeListener.shared.stop()
        // Stop AutoCAD Parallels listener
        AutoCADParallelsListener.shared.stop()
        // Tear down the CGEventTap cleanly; its run-loop source is removed.
        EventTapManager.shared.stop()
        // Stop AutoCAD command monitoring
        AutoCADCommandMonitor.shared.stop()
        // Persist overlay position one last time (window-did-move already
        // handles incremental saves, but belt-and-suspenders on quit).
        overlayController.savePosition()
    }
}

