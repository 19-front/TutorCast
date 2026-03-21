// OverlayContentView.swift
// TutorCast
//
// The visible face of the floating overlay window with adaptive font sizing,
// color-coded labels, and capsule styling for enhanced visual feedback.
//
// Dual-display modes:
//   1. Keyboard Event Mode: Displays mapped action label (e.g., "Z+", "Pn/Pan")
//   2. AutoCAD Command Mode: Displays command name (large) + subcommand/prompt (smaller)
//
// Design goals:
//   • Zero visual noise: dark pill with subtle border, no title bar chrome.
//   • Readable at a glance while screen-recording (high-contrast text).
//   • Adaptive typography: 1-3 char labels in large bold (pop visually)
//     4-5 chars in medium, >5 in smaller with hint.
//   • Color-coded by action category (navigation, zoom, edit, destructive, etc.)
//   • When displaying command: primary line (command) is large, secondary (prompt) is smaller
//   • Completely transparent *outside* the pill so underlying content shows through.
//   • The pill region is non-interactive (Text / Image only) so dragging works.

import SwiftUI

struct OverlayContentView: View {

    // ── Read persisted appearance preferences ────────────────────────────────
    @StateObject private var settingsStore = SettingsStore.shared

    // ── Observe label engine for semantic labels, commands, and color categories ───────
    @StateObject private var labelEngine = LabelEngine.shared
    
    /// Determine display mode based on LabelEngine state
    private var displayMode: DisplayMode {
        if labelEngine.isShowingCommand && !labelEngine.commandName.isEmpty {
            return .command
        } else {
            return .event
        }
    }
    
    /// Get the primary display text based on mode
    private var displayText: String {
        switch displayMode {
        case .command:
            return labelEngine.commandName
        case .event:
            return labelEngine.currentLabel
        }
    }
    
    private var labelLength: Int {
        displayText.count
    }
    
    /// Get color value from ColorCategory or theme
    private var labelColorValue: Color {
        // Commands use a distinctive cyan color
        if displayMode == .command {
            return Color(red: 0.2, green: 0.9, blue: 1.0)  // Bright cyan for commands
        }
        
        switch labelEngine.colorCategory {
        case .navigation:
            return Color(red: 1.0, green: 0.6, blue: 0.0)  // Orange
        case .zoom:
            return Color(red: 0.0, green: 1.0, blue: 1.0)  // Cyan
        case .selection:
            return Color(red: 0.0, green: 1.0, blue: 0.0)  // Green
        case .edit:
            return Color(red: 0.4, green: 0.7, blue: 1.0)  // Light Blue
        case .destructive:
            return Color(red: 1.0, green: 0.2, blue: 0.2)  // Red
        case .file:
            return Color(red: 0.8, green: 0.4, blue: 1.0)  // Purple
        case .default:
            return Color(nsColor: settingsStore.theme.textColor)
        }
    }
    
    /// Get secondary text color (for subcommand in command mode)
    private var subcommandColorValue: Color {
        return Color(nsColor: settingsStore.theme.textColor).opacity(0.7)
    }
    
    /// Adaptive font size based on label length and display mode
    private var adaptiveFontSize: Double {
        switch displayMode {
        case .command:
            // Commands: always use larger, consistent size
            return settingsStore.fontSize * 1.6
        case .event:
            switch labelLength {
            case 1...3:
                return settingsStore.fontSize * 1.8  // Large for short labels
            case 4...5:
                return settingsStore.fontSize * 1.2  // Medium
            default:
                return settingsStore.fontSize * 0.9  // Smaller for long labels
            }
        }
    }
    
    /// Font size for secondary text (subcommand prompt)
    private var subcommandFontSize: Double {
        return settingsStore.fontSize * 0.75
    }
    
    /// Adaptive weight for visual hierarchy
    private var adaptiveFontWeight: Font.Weight {
        switch displayMode {
        case .command:
            return .semibold
        case .event:
            return labelLength <= 3 ? .bold : .semibold
        }
    }
    
    /// Determine if we should use capsule background for short labels
    private var useCapsuleBackground: Bool {
        switch displayMode {
        case .command:
            return true  // Always use capsule for commands
        case .event:
            return labelLength <= 3 && labelEngine.colorCategory != .default
        }
    }
    
    /// Check if we should display two-line mode (direct AutoCAD command with secondary label)
    private var needsTwoLines: Bool {
        labelEngine.commandSource == .autoCADDirect &&
        !labelEngine.secondaryLabel.isEmpty
    }
    
    /// Padding adjustment based on label length and display mode
    private var contentPadding: EdgeInsets {
        switch displayMode {
        case .command:
            if needsTwoLines {
                return EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
            } else {
                return EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
            }
        case .event:
            if labelLength <= 3 {
                return EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
            } else if labelLength <= 5 {
                return EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
            } else {
                return EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            }
        }
    }
    
    private var bgColor: Color {
        Color(nsColor: settingsStore.theme.backgroundColor)
    }
    
    private var themeTextColor: Color {
        Color(nsColor: settingsStore.theme.textColor)
    }
    
    private var themeAccentColor: Color {
        Color(nsColor: settingsStore.theme.accentColor)
    }

    var body: some View {
        ZStack {
            // ── Background pill with optional capsule styling ──────────────
            if useCapsuleBackground {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                labelColorValue.opacity(0.15),
                                labelColorValue.opacity(0.08)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                labelColorValue.opacity(0.4),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: labelColorValue.opacity(0.3), radius: 6, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: settingsStore.theme.cornerRadius, style: .continuous)
                    .fill(bgColor.opacity(settingsStore.overlayOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: settingsStore.theme.cornerRadius, style: .continuous)
                            .strokeBorder(
                                themeAccentColor.opacity(0.3),
                                lineWidth: settingsStore.theme == .neon ? 1.5 : 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.45), radius: 8, x: 0, y: 3)
            }

            // ── Content ──────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: displayMode == .command ? 4 : (labelLength <= 3 ? 8 : 10)) {
                    // Status dot — themed accent color (hidden for very short labels and commands)
                    if labelLength > 3 && displayMode == .event {
                        Circle()
                            .fill(themeAccentColor)
                            .frame(width: 6, height: 6)
                    }

                    // Primary label (command or event)
                    Text(displayText)
                        .font(.system(
                            size: adaptiveFontSize,
                            weight: adaptiveFontWeight,
                            design: labelLength <= 3 ? .default : .rounded
                        ))
                        .foregroundStyle(labelColorValue)
                        .lineLimit(1)
                        .fixedSize()
                        .tracking(labelLength <= 3 && displayMode == .event ? 0.5 : 0)
                    
                    // Spacer to push everything to fit naturally
                    Spacer()
                        .frame(maxWidth: .infinity, maxHeight: 0)
                }
                
                // Secondary line: subcommand/prompt or secondary label (two-line mode)
                if displayMode == .command && !labelEngine.subcommandText.isEmpty {
                    Text(labelEngine.subcommandText)
                        .font(.system(
                            size: subcommandFontSize,
                            weight: .regular,
                            design: .rounded
                        ))
                        .foregroundStyle(subcommandColorValue)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                
                // Two-line mode for direct AutoCAD commands
                if needsTwoLines {
                    let truncatedSecondary = labelEngine.secondaryLabel.count > 28 ?
                        String(labelEngine.secondaryLabel.prefix(28)) + "…" :
                        labelEngine.secondaryLabel
                    
                    Text(truncatedSecondary)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(nsColor: settingsStore.theme.textColor).opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(contentPadding)
        }
        .padding(8)
        .animation(.easeInOut(duration: 0.15), value: displayText)
        .animation(.easeInOut(duration: 0.15), value: displayMode)
        .animation(.easeInOut(duration: 0.15), value: labelEngine.colorCategory)
        .animation(.easeInOut(duration: 0.15), value: labelEngine.subcommandText)
        .onChange(of: needsTwoLines) { oldValue, newValue in
            DispatchQueue.main.async {
                let newHeight: Double = newValue ? 100 : 72
                OverlayWindowController.shared.resize(to: NSSize(width: 300, height: newHeight))
            }
        }
    }
}


// MARK: - Display Mode Enum

enum DisplayMode: Equatable {
    case event
    case command
}

// MARK: - Preview

#Preview("Overlay - Short Event Label") {
    OverlayContentView()
        .frame(width: 280, height: 72)
        .background(Color.gray.opacity(0.4))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                LabelEngine.shared.currentLabel = "Z+"
                LabelEngine.shared.colorCategory = .zoom
            }
        }
}

#Preview("Overlay - Command Display") {
    OverlayContentView()
        .frame(width: 380, height: 100)
        .background(Color.gray.opacity(0.4))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                LabelEngine.shared.commandName = "LINE"
                LabelEngine.shared.subcommandText = "Specify first point:"
            }
        }
}

#Preview("Overlay - Command with Long Prompt") {
    OverlayContentView()
        .frame(width: 480, height: 100)
        .background(Color.gray.opacity(0.4))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                LabelEngine.shared.commandName = "OFFSET"
                LabelEngine.shared.subcommandText = "Specify offset distance or [Through/Erase/Layer]:"
            }
        }
}

#Preview("Overlay - Medium Event Label") {
    OverlayContentView()
        .frame(width: 320, height: 72)
        .background(Color.gray.opacity(0.4))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                LabelEngine.shared.currentLabel = "Pn/Pan"
                LabelEngine.shared.colorCategory = .navigation
            }
        }
}

#Preview("Overlay - Long Event Label") {
    OverlayContentView()
        .frame(width: 380, height: 72)
        .background(Color.gray.opacity(0.4))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                LabelEngine.shared.currentLabel = "NAVIGATE"
                LabelEngine.shared.colorCategory = .navigation
            }
        }
}
