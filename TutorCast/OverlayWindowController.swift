// OverlayWindowController.swift
// TutorCast
//
// Contains three types:
//
//   DraggableHostingView<Content>
//     └─ NSHostingView subclass that overrides mouseDownCanMoveWindow → true
//        so the SwiftUI-hosted background acts as a drag handle.
//        Interactive SwiftUI controls (Button, etc.) still swallow their own
//        mouse events, leaving the background free to start a window drag.
//
//   OverlayWindow
//     └─ Borderless, transparent, always-on-top NSWindow.
//        Configured once in configure() and never mutated afterwards.
//
//   OverlayWindowController  (@MainActor ObservableObject)
//     └─ Creates / shows / hides the window, persists frame to UserDefaults
//        via @AppStorage, and propagates isVisible to the menu bar button.

import AppKit
import SwiftUI
import Combine

// MARK: - DraggableHostingView

/// An NSHostingView that lets the window be dragged by clicking on
/// the SwiftUI content, including text areas. This makes the entire
/// overlay fully draggable even while displaying action labels.
///
/// This is achieved by overriding mouseDownCanMoveWindow to true,
/// which allows the window to be moved by clicking anywhere on the
/// hosting view except for interactive controls (not present in overlay).
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
    
    // Allow all mouse events to pass through for dragging
    override func mouseDown(with event: NSEvent) {
        // The window will use this to handle the drag
        super.mouseDown(with: event)
    }
}

// MARK: - OverlayWindow

final class OverlayWindow: NSWindow {

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect,
                   styleMask: style,
                   backing: backingStoreType,
                   defer: flag)
        configure()
    }

    private func configure() {
        // ── Appearance ───────────────────────────────────────────────────────
        // .borderless removes the title bar and all chrome.
        styleMask          = [.borderless]
        backgroundColor    = .clear          // fully transparent window shell
        isOpaque           = false           // required for transparency to work
        hasShadow          = false           // SwiftUI layer provides its own shadow

        // ── Level ────────────────────────────────────────────────────────────
        // .floating sits above normal windows but below screen savers and HUDs.
        // Use .statusBar or .mainMenu if you need it above full-screen apps.
        level              = .floating

        // ── Behaviour ────────────────────────────────────────────────────────
        // .canJoinAllSpaces  → visible on every Mission Control space.
        // .stationary        → does NOT move when switching spaces (stays put).
        // .fullScreenAuxiliary → remains visible when another app goes full-screen.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Drag by background (works in tandem with DraggableHostingView above).
        isMovableByWindowBackground = true

        // Prevent the overlay from becoming the key window — this lets
        // AutoCAD (or any other app) keep keyboard focus while the overlay
        // is visible, which is exactly what we want for monitoring shortcuts.
        // Key/main status is only acquired explicitly when settings are opened.
        // (The overlay itself has no text fields or interactive controls.)
        // Note: canBecomeKey is overridden below for safety.
    }

    // Prevent this window from stealing key status automatically.
    override var canBecomeKey:  Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - OverlayWindowController

@MainActor
final class OverlayWindowController: NSObject, ObservableObject {

    // ── Shared singleton instance ────────────────────────────────────────────
    static let shared = OverlayWindowController()

    // ── Persisted state ──────────────────────────────────────────────────────
    // @AppStorage automatically reads/writes UserDefaults(suiteName: nil).
    // Values survive app restarts so the overlay remembers its position.
    @AppStorage("overlay.x")      private var savedX:      Double = 200
    @AppStorage("overlay.y")      private var savedY:      Double = 200
    @AppStorage("overlay.width")  private var savedWidth:  Double = 300
    @AppStorage("overlay.height") private var savedHeight: Double = 72

    // ── Published state (drives menu bar button label) ───────────────────────
    @Published private(set) var isVisible: Bool = false

    // ── Private ──────────────────────────────────────────────────────────────
    private var window: OverlayWindow?

    // MARK: Public API

    func showOverlay() {
        if window == nil { buildWindow() }
        window?.orderFrontRegardless()   // show without stealing key status
        isVisible = true
    }

    func hideOverlay() {
        window?.orderOut(nil)
        isVisible = false
    }

    func toggleOverlay() {
        isVisible ? hideOverlay() : showOverlay()
    }

    /// Called by AppDelegate on quit for a final frame save.
    func savePosition() {
        guard let w = window else { return }
        savedX      = w.frame.origin.x
        savedY      = w.frame.origin.y
        savedWidth  = w.frame.width
        savedHeight = w.frame.height
    }

    // MARK: - Window Construction

    private func buildWindow() {
        // ── Validate / clamp saved frame to visible screen area ──────────────
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: savedX, y: savedY)
        let size   = NSSize(width: max(120, savedWidth), height: max(40, savedHeight))

        // Clamp so at least the top-left corner is on-screen.
        origin.x = max(screenFrame.minX, min(origin.x, screenFrame.maxX - size.width))
        origin.y = max(screenFrame.minY, min(origin.y, screenFrame.maxY - size.height))

        let frame = NSRect(origin: origin, size: size)

        // ── Create window ────────────────────────────────────────────────────
        let win = OverlayWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // ── Embed SwiftUI content ────────────────────────────────────────────
        // DraggableHostingView forwards mouseDownCanMoveWindow = true so that
        // clicking on the transparent background starts a window drag.
        let hostingView = DraggableHostingView(rootView: OverlayContentView())
        hostingView.frame = win.contentView?.bounds ?? NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        win.contentView = hostingView

        // ── Persist position whenever the window is moved ────────────────────
        NotificationCenter.default.addObserver(self, selector: #selector(overlayWindowDidMove(_:)), name: NSWindow.didMoveNotification, object: win)

        // Also persist when resized (only via code for now, but future-proof).
        NotificationCenter.default.addObserver(self, selector: #selector(overlayWindowDidResize(_:)), name: NSWindow.didResizeNotification, object: win)

        self.window = win
    }

    // MARK: - Notification Handlers

    @objc private func overlayWindowDidMove(_ notification: Notification) {
        // We're already delivered on the main runloop by NotificationCenter for NSWindow notifications.
        // savePosition() is @MainActor-isolated; call directly.
        savePosition()
    }

    @objc private func overlayWindowDidResize(_ notification: Notification) {
        savePosition()
    }

    // MARK: - Programmatic Resize Helper

    /// Resize the overlay from code (e.g. when AutoCAD command text changes length).
    /// - Parameter size: New content size; the window repositions to keep its top-left fixed.
    @MainActor
    func resize(to size: NSSize) {
        guard let w = window else { return }
        let origin = w.frame.origin
        let frame = NSRect(origin: origin, size: size)
        w.setFrame(frame, display: true, animate: true)
    }
}

