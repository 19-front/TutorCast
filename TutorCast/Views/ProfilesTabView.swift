import SwiftUI

/// Main profiles management interface with sidebar list and editing panel
struct ProfilesTabView: View {
    @StateObject private var settingsStore = SettingsStore.shared
    
    @State private var selectedProfile: Profile? = nil
    @State private var selectedMappingID: UUID? = nil
    @State private var showMappingEditor = false
    @State private var editingMapping: ActionMapping? = nil
    @State private var showNewProfileAlert = false
    @State private var newProfileName = ""
    @State private var showDeleteConfirmation = false
    @State private var profileToDelete: Profile? = nil
    @State private var showMappingDeleteConfirmation = false
    @State private var mappingToDelete: ActionMapping? = nil
    @State private var profileNameEditMode: UUID? = nil
    @State private var editedName = ""
    
    
    var body: some View {
        HStack(spacing: 0) {
            sidebarView
            Divider()
            mainPanelView
        }
        .frame(minHeight: 500)
        .onAppear {
            selectedProfile = settingsStore.currentProfile ?? settingsStore.profiles.first
        }
        .alert("New Profile", isPresented: $showNewProfileAlert, actions: newProfileAlertActions, message: newProfileAlertMessage)
        .confirmationDialog(
            "Delete Profile?",
            isPresented: $showDeleteConfirmation,
            presenting: profileToDelete,
            actions: deleteProfileActions,
            message: deleteProfileMessage
        )
        .confirmationDialog(
            "Delete Mapping?",
            isPresented: $showMappingDeleteConfirmation,
            presenting: mappingToDelete,
            actions: deleteMappingActions,
            message: deleteMappingMessage
        )
        .sheet(isPresented: $showMappingEditor, content: mappingEditorSheetContent)
    }
    
    // MARK: - Alert & Dialog Content
    
    @ViewBuilder
    private func newProfileAlertActions() -> some View {
        TextField("Profile name", text: $newProfileName)
        Button("Cancel", role: .cancel) { }
        Button("Create") {
            if !newProfileName.trimmingCharacters(in: .whitespaces).isEmpty {
                settingsStore.addProfile(named: newProfileName)
                newProfileName = ""
            }
        }
    }
    
    @ViewBuilder
    private func newProfileAlertMessage() -> some View {
        EmptyView()
    }
    
    @ViewBuilder
    private func deleteProfileActions(profile: Profile) -> some View {
        Button("Delete", role: .destructive) {
            if let index = settingsStore.profiles.firstIndex(where: { $0.id == profile.id }) {
                settingsStore.deleteProfile(at: index)
                selectedProfile = settingsStore.profiles.first
            }
        }
    }
    
    @ViewBuilder
    private func deleteProfileMessage(profile: Profile) -> some View {
        Text("Are you sure you want to delete the profile '\(profile.name)'? This action cannot be undone.")
    }
    
    @ViewBuilder
    private func deleteMappingActions(mapping: ActionMapping) -> some View {
        Button("Delete", role: .destructive) {
            if var updated = selectedProfile {
                updated.mappings.removeAll { $0.id == mapping.id }
                settingsStore.updateMappings(for: updated, mappings: updated.mappings)
                selectedProfile = updated
                mappingToDelete = nil
            }
        }
    }
    
    @ViewBuilder
    private func deleteMappingMessage(mapping: ActionMapping) -> some View {
        Text("Delete '\(mapping.label)' mapping for \(mapping.trigger.eventDescription)?")
    }
    
    @ViewBuilder
    private func mappingEditorSheetContent() -> some View {
        if let editingMapping = editingMapping, let profile = selectedProfile {
            MappingEditorWrapper(
                mapping: editingMapping,
                profile: profile,
                settingsStore: settingsStore,
                selectedProfile: $selectedProfile,
                showMappingEditor: $showMappingEditor,
                editingMapping: $editingMapping
            )
        }
    }
    
    // MARK: - Computed View Properties
    
    private var sidebarView: some View {
        VStack(spacing: 0) {
            sidebarHeaderView
            Divider()
            sidebarProfileListView
            Divider()
            sidebarButtonsView
        }
        .frame(width: 240)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var sidebarHeaderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profiles")
                .font(.headline)
            Text("Manage action shortcuts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var sidebarProfileListView: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(settingsStore.profiles) { profile in
                    profileListItem(profile)
                }
            }
            .padding(8)
        }
    }
    
    private var sidebarButtonsView: some View {
        HStack(spacing: 8) {
            Button(action: { showNewProfileAlert = true }) {
                Label("", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .help("Create new profile")
            
            if let selected = selectedProfile, selected.isCustom {
                Button(action: { profileToDelete = selected; showDeleteConfirmation = true }) {
                    Label("", systemImage: "minus.circle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                }
                .help("Delete profile")
                
                Button(action: { settingsStore.duplicateProfile(selected) }) {
                    Label("", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .help("Duplicate profile")
            }
        }
        .buttonStyle(.bordered)
        .padding(8)
    }
    
    private var mainPanelView: some View {
        Group {
            if let profile = selectedProfile {
                VStack(spacing: 0) {
                    profileHeaderView(profile)
                    Divider()
                    mappingListView(profile)
                }
            } else {
                emptyStateView
            }
        }
    }
    
    private func profileHeaderView(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                profileHeaderNameSection(profile)
                Spacer()
                profileHeaderActivationSection(profile)
                if profile.isCustom && profileNameEditMode != profile.id {
                    profileHeaderMenuSection(profile)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func profileHeaderNameSection(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if profileNameEditMode == profile.id {
                profileNameEditingView(profile)
            } else {
                Text(profile.name)
                    .font(.headline)
                Text(profile.isCustom ? "Custom Profile" : "Built-in Profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func profileNameEditingView(_ profile: Profile) -> some View {
        HStack(spacing: 8) {
            TextField("Profile name", text: $editedName)
                .textFieldStyle(.roundedBorder)
            
            Button("✓") {
                if !editedName.trimmingCharacters(in: .whitespaces).isEmpty {
                    settingsStore.renameProfile(profile, to: editedName)
                    profileNameEditMode = nil
                    selectedProfile = settingsStore.profiles.first(where: { $0.id == profile.id })
                }
            }
            .buttonStyle(.bordered)
            
            Button("✕") {
                profileNameEditMode = nil
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func profileHeaderActivationSection(_ profile: Profile) -> some View {
        Group {
            if settingsStore.activeProfileID == profile.id.uuidString {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button(action: { settingsStore.setActiveProfile(profile) }) {
                    Text("Activate")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private func profileHeaderMenuSection(_ profile: Profile) -> some View {
        Menu {
            Button("Edit Name") {
                editedName = profile.name
                profileNameEditMode = profile.id
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
    }
    
    private func mappingListView(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            mappingListHeaderView
            Divider()
            mappingListContentView(profile)
            Divider()
            mappingListButtonView(profile)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var mappingListHeaderView: some View {
        HStack(spacing: 0) {
            Text("Event")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Label")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 80, alignment: .center)
            
            Text("Category")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 120, alignment: .leading)
            
            Text("")
                .frame(width: 40, alignment: .center)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    @ViewBuilder
    private func mappingListContentView(_ profile: Profile) -> some View {
        if profile.mappings.isEmpty {
            mappingListEmptyStateView
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(profile.mappings) { mapping in
                        mappingRowView(mapping, profile: profile)
                    }
                }
            }
        }
    }
    
    private var mappingListEmptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 4) {
                Text("No mappings yet")
                    .font(.headline)
                Text("Add your first action mapping")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    private func mappingListButtonView(_ profile: Profile) -> some View {
        HStack(spacing: 8) {
            Button(action: { addNewMapping(to: profile) }) {
                Label("Add Mapping", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(8)
    }
    
    private var emptyStateView: some View {
        VStack {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("Select a profile")
                .font(.headline)
            Text("Choose a profile from the list to view and edit its mappings")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }
    
    @ViewBuilder
    private func profileListItem(_ profile: Profile) -> some View {
        Button(action: { selectedProfile = profile }) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .lineLimit(1)
                    Text("\(profile.mappings.count) actions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if !profile.isCustom {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if settingsStore.activeProfileID == profile.id.uuidString {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(8)
            .background(
                selectedProfile?.id == profile.id ?
                Color.blue.opacity(0.15) :
                Color(nsColor: .controlBackgroundColor)
            )
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func mappingRowView(_ mapping: ActionMapping, profile: Profile) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                mappingRowEventSection(mapping)
                mappingRowLabelSection(mapping)
                mappingRowCategorySection(mapping)
                mappingRowActionsSection(mapping)
            }
            Divider()
        }
    }
    
    private func mappingRowEventSection(_ mapping: ActionMapping) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(mapping.trigger.eventDescription)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }
    
    private func mappingRowLabelSection(_ mapping: ActionMapping) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(
                    red: mapping.colorCategory.color.red,
                    green: mapping.colorCategory.color.green,
                    blue: mapping.colorCategory.color.blue
                ))
                .frame(width: 8, height: 8)
            
            Text(mapping.label)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
        }
        .frame(width: 80, alignment: .center)
        .padding(8)
    }
    
    private func mappingRowCategorySection(_ mapping: ActionMapping) -> some View {
        Text(mapping.colorCategory.displayName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: 120, alignment: .leading)
            .padding(8)
    }
    
    private func mappingRowActionsSection(_ mapping: ActionMapping) -> some View {
        HStack(spacing: 4) {
            Button(action: { editMapping(mapping) }) {
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .help("Edit")
            
            Button(action: { mappingToDelete = mapping; showMappingDeleteConfirmation = true }) {
                Image(systemName: "trash.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .frame(width: 40, alignment: .center)
        .padding(8)
    }
    
    private func editMapping(_ mapping: ActionMapping) {
        editingMapping = mapping
        showMappingEditor = true
    }
    
    private func addNewMapping(to profile: Profile) {
        let newMapping = ActionMapping(
            trigger: ActionTrigger(eventDescription: "New Input"),
            label: "New",
            colorCategory: .default
        )
        editingMapping = newMapping
        showMappingEditor = true
    }
}

// MARK: - Preview

#Preview {
    ProfilesTabView()
        .frame(height: 600)
}

// MARK: - MappingEditorWrapper

/// Wrapper view to handle MappingEditorView logic separately
private struct MappingEditorWrapper: View {
    let mapping: ActionMapping
    let profile: Profile
    let settingsStore: SettingsStore
    
    @Binding var selectedProfile: Profile?
    @Binding var showMappingEditor: Bool
    @Binding var editingMapping: ActionMapping?
    
    var body: some View {
        MappingEditorView(
            mapping: mapping,
            onSave: handleSave
        )
    }
    
    private func handleSave(updated: ActionMapping) {
        var updatedProfile = profile
        if let index = updatedProfile.mappings.firstIndex(where: { $0.id == mapping.id }) {
            updatedProfile.mappings[index] = updated
        } else {
            updatedProfile.mappings.append(updated)
        }
        settingsStore.updateMappings(for: updatedProfile, mappings: updatedProfile.mappings)
        selectedProfile = updatedProfile
        showMappingEditor = false
        editingMapping = nil
    }
}
