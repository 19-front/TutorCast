import SwiftUI
import Combine

struct GeneralSettingsView: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        Form {
            HStack {
                Text("Opacity")
                Slider(value: Binding(get: { max(0.3, min(1.0, store.overlayOpacity)) }, set: { store.overlayOpacity = max(0.3, min(1.0, $0)) }), in: 0.3...1.0, step: 0.01)
                Text("\(Int(store.overlayOpacity * 100))%")
                    .frame(width: 50, alignment: .trailing)
            }
            Stepper(value: $store.fontSize, in: 10...64, step: 1) {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Text("\(Int(store.fontSize)) pt")
                }
            }
            Picker("Theme", selection: $store.theme) {
                Text("Minimal").tag(SettingsStore.Theme.minimal)
                Text("Neon").tag(SettingsStore.Theme.neon)
                Text("AutoCAD").tag(SettingsStore.Theme.autoCAD)
            }
            .pickerStyle(.segmented)
        }
        .padding()
    }
}

struct ProfilesSettingsView: View {
    @EnvironmentObject var store: SettingsStore
    @State private var selectedProfileID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar with profiles
            VStack(alignment: .leading) {
                HStack {
                    Text("Profiles").font(.headline)
                    Spacer()
                    Button("+") { store.addProfile() }
                }
                List(selection: $selectedProfileID) {
                    ForEach(store.profiles) { profile in
                        Text(profile.name)
                            .tag(profile.id as UUID?)
                    }
                    .onDelete { indexSet in
                        for index in indexSet.sorted(by: >) {
                            deleteProfile(at: index)
                        }
                    }
                }
                .frame(minWidth: 180, maxWidth: 220, minHeight: 300)
                HStack {
                    Button("Rename") {
                        guard let id = selectedProfileID, let p = store.profiles.first(where: { $0.id == id }) else { return }
                        let newName = p.name + " (Renamed)"
                        store.renameProfile(p, to: newName)
                    }
                    Button("Delete") {
                        if let id = selectedProfileID, let idx = store.profiles.firstIndex(where: { $0.id == id }) {
                            store.deleteProfile(at: idx)
                            selectedProfileID = store.profiles.first?.id
                        }
                    }
                }
            }
            Divider()
            // Detail with mappings table
            if let current = currentProfile {
                VStack(alignment: .leading) {
                    HStack {
                        Text(current.name).font(.title2)
                        Spacer()
                        Button("Load Profile") {
                            store.setActiveProfile(current)
                        }
                    }
                    MappingsTableView(profile: current) { updated in
                        store.updateMappings(for: current, mappings: updated)
                    }
                }
                .padding()
            } else {
                VStack { Text("Select or create a profile") }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selectedProfileID == nil { selectedProfileID = store.activeProfile()?.id ?? store.profiles.first?.id }
        }
        .frame(minWidth: 720, minHeight: 420)
        .padding(.vertical)
    }
    
    private func deleteProfile(at index: Int) {
        store.deleteProfile(at: index)
        // Update selection if needed
        if let selected = selectedProfileID, !store.profiles.contains(where: { $0.id == selected }) {
            selectedProfileID = store.profiles.first?.id
        }
    }

    private var currentProfile: Profile? {
        if let id = selectedProfileID { return store.profiles.first(where: { $0.id == id }) }
        return nil
    }
}

struct MappingsTableView: View {
    var profile: Profile
    var onChange: ([ActionMapping]) -> Void
    @State private var rows: [ActionMapping]

    init(profile: Profile, onChange: @escaping ([ActionMapping]) -> Void) {
        self.profile = profile
        self.onChange = onChange
        _rows = State(initialValue: profile.mappings)
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Action").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                Text("Display Label").font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 60)
            }
            List {
                ForEach(rows) { row in
                    HStack {
                        TextField(
                            "Action",
                            text: Binding(
                                get: { row.trigger.eventDescription },
                                set: { newValue in
                                    if let idx = rows.firstIndex(where: { $0.id == row.id }) {
                                        let updated = ActionMapping(id: rows[idx].id, trigger: ActionTrigger(id: rows[idx].trigger.id, eventDescription: newValue), label: rows[idx].label, colorCategory: rows[idx].colorCategory)
                                        rows[idx] = updated
                                        onChange(rows)
                                    }
                                }
                            )
                        )
                        TextField(
                            "Label",
                            text: Binding(
                                get: { row.label },
                                set: { newValue in
                                    if let idx = rows.firstIndex(where: { $0.id == row.id }) {
                                        let updated = ActionMapping(id: rows[idx].id, trigger: rows[idx].trigger, label: newValue, colorCategory: rows[idx].colorCategory)
                                        rows[idx] = updated
                                        onChange(rows)
                                    }
                                }
                            )
                        )
                        Button(role: .destructive) {
                            if let idx = rows.firstIndex(where: { $0.id == row.id }) {
                                rows.remove(at: idx)
                                onChange(rows)
                            }
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                }
                .onMove { indices, newOffset in
                    rows.move(fromOffsets: indices, toOffset: newOffset)
                    onChange(rows)
                }
            }
            HStack {
                Button("Add Mapping") {
                    rows.append(ActionMapping(trigger: ActionTrigger(eventDescription: ""), label: "", colorCategory: .default))
                    onChange(rows)
                }
                Spacer()
            }
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, ObservableObject {
    private var window: NSWindow?
    let store: SettingsStore
    let objectWillChange = PassthroughSubject<Void, Never>()

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let content = TabView {
                GeneralSettingsView().tabItem { Text("General") }
                ProfilesSettingsView().tabItem { Text("Profiles") }
            }
            .environmentObject(store)
            let hosting = NSHostingController(rootView: content)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Settings"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 780, height: 520))
            window = win
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

