import AppKit

// Simple keyboard shortcut handler using NSEvent monitoring
// Registers for global hotkey events

@MainActor
final class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()
    
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var onToggleOverlay: (() -> Void)?
    
    func registerToggleOverlayHotkey(action: @escaping () -> Void) {
        self.onToggleOverlay = action
        
        // Monitor for Ctrl+Option+Cmd+K
        // In macOS, this requires using NSEvent.addGlobalMonitorForEvents
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.checkHotkey(event)
        }
        
        print("[KeyboardShortcutManager] ⌃⌥⌘K hotkey registered (global monitoring enabled)")
    }
    
    private func checkHotkey(_ event: NSEvent) {
        // Check for Ctrl+Option+Cmd+K
        // keyCode 40 = K key on US keyboard
        let hasCtrl = event.modifierFlags.contains(.control)
        let hasOption = event.modifierFlags.contains(.option)
        let hasCmd = event.modifierFlags.contains(.command)
        let isKKey = event.keyCode == 40
        
        if hasCtrl && hasOption && hasCmd && isKKey {
            DispatchQueue.main.async { [weak self] in
                self?.onToggleOverlay?()
            }
        }
    }
    
    func unregisterHotkey() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }
    
    deinit {
        Task { @MainActor in
            self.unregisterHotkey()
        }
    }
}
