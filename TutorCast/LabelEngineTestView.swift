import SwiftUI

/// Helper view for testing the LabelEngine directly from previews
/// Use: KeyMouseMonitor.shared.simulate(event: "Middle Drag") to trigger
struct LabelEngineTestView: View {
    @ObservedObject private var labelEngine = LabelEngine.shared
    @ObservedObject private var settingsStore = SettingsStore.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("LabelEngine Test")
                .font(.headline)

            // Display current state
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Active Profile:")
                        .fontWeight(.semibold)
                    Text(settingsStore.activeProfile()?.name ?? "None")
                        .foregroundStyle(.blue)
                }
                HStack {
                    Text("Current Label:")
                        .fontWeight(.semibold)
                    Text(String(describing: labelEngine.currentLabel))
                        .foregroundStyle(colorForLabelColor((labelEngine as AnyObject).value(forKey: "labelColor") as? String ?? ""))
                }
            }
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)

            Divider()

            // Test buttons for AutoCAD profile
            VStack(alignment: .leading, spacing: 10) {
                Text("Simulate AutoCAD Events:")
                    .fontWeight(.semibold)

                ForEach(["Left Click", "Middle Drag", "Scroll Up", "Scroll Down", "⌘ + Z"], id: \.self) { event in
                    Button(action: { KeyMouseMonitor.shared.simulate(event: event) }) {
                        Text(event)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Divider()

            // Test buttons for direct command events (Section 13 Integration Tests)
            VStack(alignment: .leading, spacing: 10) {
                Text("Simulate Direct Command Events:")
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)

                // Simulate LINE command start
                Button(action: {
                    LabelEngine.shared.processCommandEvent(AutoCADCommandEvent(
                        type: .commandStarted,
                        commandName: "LINE",
                        subcommand: nil,
                        activeOptions: nil,
                        timestamp: Date(),
                        source: .nativePlugin
                    ))
                    print("[Test] Simulated LINE start event")
                }) {
                    HStack {
                        Image(systemName: "line.diagonal")
                        Text("Simulate LINE start")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                // Simulate subcommand prompt
                Button(action: {
                    LabelEngine.shared.processCommandEvent(AutoCADCommandEvent(
                        type: .subcommandPrompt,
                        commandName: "LINE",
                        subcommand: "Specify first point",
                        activeOptions: nil,
                        timestamp: Date(),
                        source: .nativePlugin
                    ))
                    print("[Test] Simulated LINE subcommand prompt")
                }) {
                    HStack {
                        Image(systemName: "text.bubble")
                        Text("Simulate subcommand prompt")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                // Simulate OFFSET with options
                Button(action: {
                    LabelEngine.shared.processCommandEvent(AutoCADCommandEvent(
                        type: .subcommandPrompt,
                        commandName: "OFFSET",
                        subcommand: "Specify offset distance",
                        activeOptions: ["Through", "Erase", "Layer"],
                        timestamp: Date(),
                        source: .parallelsPlugin
                    ))
                    print("[Test] Simulated OFFSET options event")
                }) {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text("Simulate OFFSET options")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                // Simulate command cancelled
                Button(action: {
                    LabelEngine.shared.processCommandEvent(AutoCADCommandEvent(
                        type: .commandCancelled,
                        commandName: "LINE",
                        subcommand: nil,
                        activeOptions: nil,
                        timestamp: Date(),
                        source: .nativePlugin
                    ))
                    print("[Test] Simulated command cancelled")
                }) {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Simulate command cancelled")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                // Simulate option selected
                Button(action: {
                    LabelEngine.shared.processCommandEvent(AutoCADCommandEvent(
                        type: .optionSelected,
                        commandName: "OFFSET",
                        subcommand: "Through",
                        activeOptions: nil,
                        timestamp: Date(),
                        source: .parallelsPlugin
                    ))
                    print("[Test] Simulated option selected: Through")
                }) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Simulate option selected")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }

            Divider()

            // Profile selector
            VStack(alignment: .leading, spacing: 10) {
                Text("Switch Profile:")
                    .fontWeight(.semibold)

                ForEach(settingsStore.profiles) { profile in
                    Button(action: { settingsStore.setActiveProfile(profile) }) {
                        HStack {
                            Text(profile.name)
                            Spacer()
                            if settingsStore.activeProfile()?.id == profile.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
        .padding()
    }

    private func colorForLabelColor(_ color: String) -> Color {
        switch color {
        case "orange": return Color(red: 1.0, green: 0.6, blue: 0.0)
        case "cyan": return Color(red: 0.0, green: 1.0, blue: 1.0)
        case "green": return Color(red: 0.0, green: 1.0, blue: 0.0)
        case "red": return Color(red: 1.0, green: 0.2, blue: 0.2)
        default: return .white
        }
    }
}

#Preview {
    LabelEngineTestView()
}
