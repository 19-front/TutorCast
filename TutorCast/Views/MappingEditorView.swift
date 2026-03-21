import SwiftUI

/// Modal sheet for editing an individual ActionMapping
/// Allows capture of input, label customization, and color category selection
struct MappingEditorView: View {
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var labelEngine = LabelEngine.shared
    @State private var isCapturing = false
    @State private var capturedEventDescription: String = ""
    
    @State var mapping: ActionMapping
    @State var onSave: (ActionMapping) -> Void
    
    @State private var label: String = ""
    @State private var colorCategory: ColorCategory = .default
    @State private var validationError: String = ""
    @State private var showValidationError = false
    
    private var isValid: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty &&
        label.count <= 8
    }
    
    private var charCountText: String {
        "\(label.count)/8 chars"
    }
    
    private var isShortLabel: Bool {
        label.count <= 3
    }

    var body: some View {
        VStack(spacing: 20) {
            // ── Header ──────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Edit Action Mapping")
                    .font(.headline)
                Text("Configure how this action appears on the overlay")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            ScrollView {
                VStack(spacing: 16) {
                    // ── Event Capture Section ───────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Input Event", systemImage: "keyboard.badge.eye.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mapping.trigger.eventDescription)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                
                                if isCapturing {
                                    Text("Listening for input…")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                        .animation(.easeInOut, value: isCapturing)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Button(action: { isCapturing.toggle() }) {
                                Label(
                                    isCapturing ? "Cancel" : "Recapture",
                                    systemImage: isCapturing ? "xmark.circle.fill" : "arrow.clockwise"
                                )
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    Divider()
                    
                    // ── Label Section ───────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Display Label", systemImage: "tag.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Text("Short labels (1–3 chars) display best. Max 8 characters.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        TextField("Enter label", text: $label)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: isShortLabel ? .default : .monospaced))
                            .onChange(of: label) { _, newValue in
                                // Enforce max 8 chars
                                if newValue.count > 8 {
                                    label = String(newValue.prefix(8))
                                }
                                validationError = ""
                            }
                        
                        HStack {
                            Text(charCountText)
                                .font(.caption)
                                .foregroundStyle(isShortLabel ? .green : .orange)
                            
                            Spacer()
                            
                            if isShortLabel {
                                Label("Perfect for overlay", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if label.count <= 5 {
                                Label("Good", systemImage: "info.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else if label.count > 5 {
                                Label("Longer labels may clutter", systemImage: "exclamationmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    
                    // ── Live Preview ────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                            
                            VStack {
                                Text(label.isEmpty ? "Label" : label)
                                    .font(.system(
                                        size: isShortLabel ? 36 : (label.count <= 5 ? 28 : 20),
                                        weight: isShortLabel ? .bold : .semibold,
                                        design: isShortLabel ? .default : .rounded
                                    ))
                                    .foregroundStyle(Color(red: colorCategory.color.red, green: colorCategory.color.green, blue: colorCategory.color.blue))
                            }
                            .padding(16)
                        }
                        .frame(height: 80)
                    }
                    
                    Divider()
                    
                    // ── Color Category Section ──────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Visual Category", systemImage: "paintpalette.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Picker("Color Category", selection: $colorCategory) {
                            ForEach(ColorCategory.allCases) { category in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(
                                            red: category.color.red,
                                            green: category.color.green,
                                            blue: category.color.blue
                                        ))
                                        .frame(width: 12, height: 12)
                                    
                                    Text(category.displayName)
                                }
                                .tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding(16)
            }
            
            // ── Error Message ───────────────────────────────────────────────
            if showValidationError {
                VStack(alignment: .leading, spacing: 4) {
                    Label(validationError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
                .transition(.opacity)
            }
            
            // ── Buttons ─────────────────────────────────────────────────────
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: save) {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear {
            label = mapping.label
            colorCategory = mapping.colorCategory
        }
    }
    
    private func save() {
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        
        guard !trimmedLabel.isEmpty else {
            validationError = "Label cannot be empty"
            showValidationError = true
            return
        }
        
        guard trimmedLabel.count <= 8 else {
            validationError = "Label must be 8 characters or less"
            showValidationError = true
            return
        }
        
        var updatedMapping = mapping
        updatedMapping.label = trimmedLabel
        updatedMapping.colorCategory = colorCategory
        
        onSave(updatedMapping)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    MappingEditorView(
        mapping: ActionMapping(
            trigger: ActionTrigger(eventDescription: "Middle Drag"),
            label: "Pn",
            colorCategory: .navigation
        ),
        onSave: { _ in }
    )
}
