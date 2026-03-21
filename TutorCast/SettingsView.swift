// SettingsView.swift
// TutorCast
//
// Opened via Cmd+, (the SwiftUI Settings scene) or the menu bar "Settings…" item.
// Contains multiple tabs: Appearance, Profiles, Keyboard Shortcuts, Permissions, etc.

import SwiftUI

struct SettingsView: View {
    @StateObject private var settingsStore = SettingsStore.shared
    @State private var selectedTab: SettingsTab = .appearance
    
    enum SettingsTab: String, CaseIterable, Identifiable {
        case appearance = "Appearance"
        case profiles = "Profiles"
        case keyboard = "Keyboard"
        case autoCAD = "AutoCAD"
        case permissions = "Permissions"
        case about = "About"
        
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .appearance: return "paintpalette.fill"
            case .profiles: return "slider.horizontal.3"
            case .keyboard: return "keyboard.fill"
            case .autoCAD: return "cable.connector"
            case .permissions: return "lock.fill"
            case .about: return "info.circle.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Tab Bar ──────────────────────────────────────────────────────
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { tab in
                    tabButton(for: tab)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // ── Tab Content ──────────────────────────────────────────────────
            TabView(selection: $selectedTab) {
                AppearanceTab()
                    .tag(SettingsTab.appearance)
                
                ProfilesTabView()
                    .tag(SettingsTab.profiles)
                
                KeyboardTab()
                    .tag(SettingsTab.keyboard)
                
                AutoCADTab()
                    .tag(SettingsTab.autoCAD)
                
                PermissionsTab()
                    .tag(SettingsTab.permissions)
                
                AboutTab()
                    .tag(SettingsTab.about)
            }
            .tabViewStyle(.automatic)
        }
        .frame(width: 700, height: 650)
    }
    
    @ViewBuilder
    private func tabButton(for tab: SettingsTab) -> some View {
        Button(action: { selectedTab = tab }) {
            Label(tab.rawValue, systemImage: tab.icon)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .opacity(selectedTab == tab ? 1.0 : 0.6)
    }
}

// MARK: - Appearance Tab

struct AppearanceTab: View {
    @StateObject private var settingsStore = SettingsStore.shared

    var body: some View {
        Form {
            Section("Overlay Appearance") {
                LabeledContent("Theme") {
                    Picker("Theme", selection: $settingsStore.theme) {
                        ForEach(SettingsStore.Theme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                }

                LabeledContent("Background opacity") {
                    HStack {
                        Slider(value: $settingsStore.overlayOpacity, in: 0.3...1.0, step: 0.05)
                            .frame(width: 140)
                        Text(String(format: "%.0f%%", settingsStore.overlayOpacity * 100))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                LabeledContent("Font size") {
                    HStack {
                        Slider(value: $settingsStore.fontSize, in: 10...32, step: 1)
                            .frame(width: 140)
                        Text(String(format: "%.0f pt", settingsStore.fontSize))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
            
            Section("Theme Preview") {
                HStack {
                    Circle()
                        .fill(Color(nsColor: settingsStore.theme.accentColor))
                        .frame(width: 7, height: 7)
                    Text("Sample: \(settingsStore.theme.displayName) theme")
                        .font(.system(
                            size: settingsStore.fontSize,
                            weight: settingsStore.theme == .neon ? .bold : .semibold,
                            design: .rounded
                        ))
                        .foregroundStyle(Color(nsColor: settingsStore.theme.textColor))
                }
                .padding(12)
                .background(Color(nsColor: settingsStore.theme.backgroundColor))
                .cornerRadius(settingsStore.theme.cornerRadius)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Keyboard Tab

struct KeyboardTab: View {
    var body: some View {
        Form {
            Section("Keyboard Shortcuts") {
                LabeledContent("Toggle Overlay", value: "⌃⌥⌘K")
                LabeledContent("Show/Hide", value: "⇧⌘O")
                LabeledContent("Settings", value: "⌘,")
            }
            
            Section("Tips") {
                Text("Use these shortcuts while recording to quickly toggle the overlay on and off without breaking your workflow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - AutoCAD Tab

struct AutoCADTab: View {
    @StateObject private var settingsStore = SettingsStore.shared
    @State private var connectionStatus: String = "Not detected"
    @State private var isCheckingConnection: Bool = false
    
    var body: some View {
        Form {
            // Section: Connection Status
            Section("Connection Status") {
                HStack(spacing: 12) {
                    // Status badge
                    Circle()
                        .fill(statusBadgeColor)
                        .frame(width: 12, height: 12)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectionStatus)
                            .font(.system(size: 13, weight: .semibold))
                        Text("AutoCAD plugin detection")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                
                Button(action: redetectConnection) {
                    Label("Re-detect", systemImage: "arrowtriangle.2.counterclockwise.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
                .disabled(isCheckingConnection)
                
                // Manual override picker
                LabeledContent("Environment") {
                    Picker("AutoCAD Environment", selection: $settingsStore.environmentOverride) {
                        Text("Auto-detect").tag("")
                        Text("macOS native").tag("native")
                        Text("Parallels VM").tag("parallels")
                    }
                    .pickerStyle(.menu)
                }
                
                // IP address field (visible only for Parallels manual mode)
                if settingsStore.environmentOverride == "parallels" {
                    LabeledContent("Parallels IP") {
                        TextField("192.168.x.x", text: $settingsStore.parallelsManualIP)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }
            }
            
            // Section: Plugin Installation
            Section("Plugin Installation") {
                if settingsStore.environmentOverride != "parallels" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("macOS Plugin Instructions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("Copy the AutoCAD plugin files to your AutoCAD Support folder to enable direct command capture.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Button(action: openAutoCADSupportFolder) {
                            Label("Open AutoCAD Support Folder", systemImage: "folder.circle")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Parallels VM Plugin Instructions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("Copy plugin to shared folder on the Parallels virtual machine.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Button(action: copyPluginToSharedFolder) {
                            Label("Copy plugin to shared folder", systemImage: "square.and.arrow.right.circle")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
                
                LabeledContent("Status") {
                    Text(pluginStatus)
                        .font(.caption)
                        .foregroundStyle(pluginStatusColor)
                }
            }
            
            // Section: Command Label Mapping
            Section("Command Label Mapping") {
                Toggle("Use AutoCAD direct commands", isOn: $settingsStore.directCommandsEnabled)
                    .font(.system(size: 12, weight: .semibold))
                
                Toggle("Show subcommand text", isOn: $settingsStore.showSubcommand)
                    .font(.system(size: 12, weight: .semibold))
                
                Toggle("Fallback to keyboard when disconnected", isOn: $settingsStore.fallbackToKeyboard)
                    .font(.system(size: 12, weight: .semibold))
            }
            
            // Section: Advanced
            Section("Advanced") {
                LabeledContent("TCP Port") {
                    TextField("19848", value: $settingsStore.tcpPort, format: .number)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 60)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection Timeout")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        Text("100ms")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Slider(value: Binding(
                            get: { Double(settingsStore.tcpPort) },
                            set: { _ in }
                        ), in: 100...2000, step: 100)
                        
                        Text("2s")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Button(role: .destructive, action: clearSharedFolderEvents) {
                    Label("Clear shared folder events", systemImage: "trash.circle")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    // MARK: - Helpers
    
    private var statusBadgeColor: Color {
        switch connectionStatus {
        case "Connected": return .green
        case "Not detected": return .gray
        case "Checking…": return .blue
        default: return .orange
        }
    }
    
    private var pluginStatus: String {
        "Not detected"  // TODO: Connect to actual plugin detection
    }
    
    private var pluginStatusColor: Color {
        pluginStatus == "Installed & responding" ? .green : .orange
    }
    
    private func redetectConnection() {
        isCheckingConnection = true
        connectionStatus = "Checking…"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            connectionStatus = "Not detected"
            isCheckingConnection = false
        }
    }
    
    private func openAutoCADSupportFolder() {
        let supportPath = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)[0]
        if let url = URL(string: "file://" + supportPath) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func copyPluginToSharedFolder() {
        // TODO: Implement plugin copy logic
        print("Copy plugin to shared folder")
    }
    
    private func clearSharedFolderEvents() {
        print("Clear shared folder events")
    }
}


// MARK: - Permissions Tab

struct PermissionsTab: View {
    var body: some View {
        Form {
            Section("Required Permissions") {
                LabeledContent(
                    "Input Monitoring",
                    value: "Required for keyboard capture"
                )
                Button("Open Input Monitoring Settings…") {
                    openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
                }

                LabeledContent(
                    "Accessibility",
                    value: "May be required on some macOS versions"
                )
                Button("Open Accessibility Settings…") {
                    openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                }
            }
            
            Section("Troubleshooting") {
                Button("Restart Event Tap") {
                    EventTapManager.shared.stop()
                    EventTapManager.shared.start()
                }
                .foregroundStyle(.orange)
                
                Text("Use this if keyboard/mouse input detection stops working.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "keyboard.badge.eye.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                
                Text("TutorCast")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Built for CAD creators")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Label("Real-time action display", systemImage: "keyboard.fill")
                Label("Custom action profiles", systemImage: "slider.horizontal.3")
                Label("Color-coded shortcuts", systemImage: "paintpalette.fill")
                Label("Lightweight overlay", systemImage: "sparkles")
            }
            .font(.caption)
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            
            Divider()
            
            VStack(spacing: 4) {
                Text("Designed to enhance your screen recordings with live action labels. Customize profiles to match your workflow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    Link("Documentation", destination: URL(string: "https://github.com")!)
                    Divider()
                    Link("Report Issues", destination: URL(string: "https://github.com")!)
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }
            
            VStack(spacing: 4) {
                Text("Version \(appVersion) (Build \(appBuild))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

// MARK: - Preview

#Preview("Settings") {
    SettingsView()
}
