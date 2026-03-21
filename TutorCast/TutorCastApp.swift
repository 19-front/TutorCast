// TutorCastApp.swift
// TutorCast — AutoCAD tutorial overlay for screen recording
//
// Lifecycle: AppKit + SwiftUI hybrid.
//   • @NSApplicationDelegateAdaptor bridges the SwiftUI @main entry point
//     to a classic NSApplicationDelegate for AppKit-level setup (CGEventTap,
//     window management, activation policy).
//   • MenuBarExtra drives the system-tray icon; Settings{} provides the
//     Cmd+, preferences window — both are first-class SwiftUI scenes.

import SwiftUI
import UniformTypeIdentifiers

@main
struct TutorCastApp: App {

    // Bridge to AppKit delegate for lifecycle & CGEventTap setup.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {

        // ── System-tray (menu bar) icon ────────────────────────────────────
        // menuBarExtraStyle(.menu) renders a standard NSMenu drop-down,
        // which is the correct style for a utility/overlay app.
        MenuBarExtra("TutorCast", systemImage: "keyboard.badge.eye.fill") {
            MenuBarContentView()
                .environmentObject(appDelegate.overlayController)
        }
        .menuBarExtraStyle(.menu)

        // ── Settings window ─────────────────────────────────────────────────
        // The Settings scene automatically registers Cmd+, and adds a
        // "Settings…" entry in the application menu.
        Settings {
            SettingsView()
        }
    }
}

struct MenuBarContentView: View {

    @EnvironmentObject var overlayController: OverlayWindowController
    @StateObject private var settingsStore = SettingsStore.shared
    @StateObject private var sessionRecorder = SessionRecorder.shared
    @State private var showingSavePanel = false

    var body: some View {

        // Toggle overlay visibility
        Button(overlayController.isVisible ? "Hide Overlay" : "Show Overlay") {
            overlayController.toggleOverlay()
        }
        // Global shortcut shown in the menu item label
        .keyboardShortcut("o", modifiers: [.command, .shift])

        Divider()

        // ── Profile Switcher ───────────────────────────────────────────────
        Menu("Active Profile: \(settingsStore.activeProfile()?.name ?? "None")") {
            ForEach(settingsStore.profiles) { profile in
                Button(action: { settingsStore.setActiveProfile(profile) }) {
                    HStack {
                        Text(profile.name)
                        if settingsStore.activeProfile()?.id == profile.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()
        
        // ── Session Recording ───────────────────────────────────────────────
        Button("Save Last 60 Seconds…") {
            showingSavePanel = true
        }

        Divider()

        // Open the Settings window (SwiftUI Settings scene)
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit TutorCast") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
        
        .sheet(isPresented: $showingSavePanel) {
            ExportSessionView()
        }
    }
}

// MARK: - Export Session View

struct ExportSessionView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var sessionRecorder = SessionRecorder.shared
    @State private var fileName = "tutorcast-session"
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Save Session Log")
                .font(.headline)
            
            Text("\(sessionRecorder.recordedActions.count) actions recorded in last 60 seconds")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                Text("Filename:")
                TextField("Session name", text: $fileName)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    let documentsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                    let fileURL = documentsURL.appendingPathComponent("\(fileName).txt")
                    
                    Task {
                        await sessionRecorder.exportSession(to: fileURL)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
