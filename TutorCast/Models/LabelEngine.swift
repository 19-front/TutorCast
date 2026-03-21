import Foundation
import Combine

/// LabelEngine transforms raw keyboard/mouse events and AutoCAD command state
/// into semantic labels based on the active profile's action mappings, with
/// support for custom profiles, color categories, and dynamic label rendering.
///
/// Tri-mode operation:
///   1. Keyboard/Mouse Mode: Maps keyboard shortcuts to action labels
///   2. Command Mode: Displays active AutoCAD command and subcommand directly
///   3. Command Events: Processes AutoCADCommandEvent from plugins (highest priority)
///
/// Display priority:
///   When AutoCAD command event active → show mapped command + subcommand/options
///   When AutoCAD direct command active → show command + subcommand (from monitor)
///   When keyboard event → show mapped label or raw event
///   Otherwise → show "Ready"
@MainActor
final class LabelEngine: ObservableObject {
    static let shared = LabelEngine()
    
    /// Event source for current display
    enum CommandSource {
        case keyboard          // Derived from CGEventTap (lower priority)
        case autoCADDirect     // From AutoCAD plugin events (higher priority)
    }

    // MARK: - Event-based display (keyboard shortcuts)
    @Published var currentLabel: String = "Ready"
    @Published var secondaryLabel: String = ""      // Subcommand/options text (smaller line)
    @Published var colorCategory: ColorCategory = .default
    @Published var commandSource: CommandSource = .keyboard
    
    // MARK: - Command-based display (AutoCAD direct read)
    @Published var commandName: String = ""
    @Published var subcommandText: String = ""
    @Published var isShowingCommand: Bool = false

    private let settingsStore = SettingsStore.shared
    private let autoCADMonitor = AutoCADCommandMonitor.shared
    private let nativeListener = AutoCADNativeListener.shared
    private let parallelsListener = AutoCADParallelsListener.shared
    private var cancellables = Set<AnyCancellable>()
    private var lastEventTime: Date = Date()
    private var lastDirectEventTime: Date?  // Track AutoCAD command event timing for priority
    private var displayTimer: Timer?
    private var commandEventTimer: Timer?  // Separate timer for command event clearing

    private init() {
        setupBindings()
        setupNativeListener()
        setupParallelsListener()
    }

    /// Set up reactive bindings to monitor raw events, profile changes, and AutoCAD commands
    private func setupBindings() {
        // Monitor KeyMouseMonitor for raw keyboard/mouse events
        KeyMouseMonitor.shared.$lastEvent
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.processEvent(event)
            }
            .store(in: &cancellables)

        // Monitor AutoCAD command monitor for command state changes
        autoCADMonitor.$commandName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] commandName in
                self?.commandName = commandName
                self?.updateIsShowingCommand()
            }
            .store(in: &cancellables)
        
        autoCADMonitor.$subcommandText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] subcommandText in
                self?.subcommandText = subcommandText
                self?.updateIsShowingCommand()
            }
            .store(in: &cancellables)

        // Monitor settings store for profile changes
        settingsStore.$currentProfile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Reset event display when profile changes
                self?.currentLabel = "Ready"
                self?.colorCategory = .default
            }
            .store(in: &cancellables)

        // Ensure default profile on first launch
        if settingsStore.activeProfileID.isEmpty {
            if let autoCADProfile = settingsStore.profiles.first(where: { $0.name == "AutoCAD" }) {
                settingsStore.setActiveProfile(autoCADProfile)
            }
        }
    }
    
    /// Set up native listener to receive AutoCAD command events from plugins
    private func setupNativeListener() {
        nativeListener.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.processCommandEvent(event)
            }
        }
    }
    
    /// Set up Parallels listener to receive Windows AutoCAD command events
    private func setupParallelsListener() {
        parallelsListener.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.processCommandEvent(event)
            }
        }
    }
    
    /// Process an AutoCADCommandEvent from either native or Parallels plugin
    /// This is the highest-priority input channel, suppressing keyboard events
    private func processCommandEvent(_ event: AutoCADCommandEvent) {
        lastEventTime = Date()
        lastDirectEventTime = Date()
        commandEventTimer?.invalidate()
        
        switch event.type {
        case .commandStarted:
            // Start new command: show command name + category mapping
            let label = labelForCommand(event.commandName)
            currentLabel = label.short              // 1-3 char abbreviation
            secondaryLabel = label.full             // Full command name
            colorCategory = colorForCommand(event.commandName)
            commandSource = .autoCADDirect
            
            // Longer display duration for command start
            scheduleCommandEventClear(duration: 5.0)
            
        case .subcommandPrompt:
            // Update secondary line with subcommand + options
            secondaryLabel = formatSubcommandPrompt(event.subcommand, options: event.activeOptions)
            commandSource = .autoCADDirect
            
            // Persist longer for subcommands
            scheduleCommandEventClear(duration: 8.0)
            
        case .optionSelected:
            // User picked an option: flash it briefly
            secondaryLabel = event.selectedOption ?? ""
            scheduleCommandEventClear(duration: 2.0)
            
        case .commandCompleted, .commandCancelled:
            // Command done: fade out
            scheduleCommandEventClear(duration: 0.8)
            
        case .commandLineText:
            // Fallback: raw command line text
            currentLabel = sanitizeEventDisplay(event.rawCommandLineText ?? "")
            secondaryLabel = ""
            commandSource = .autoCADDirect
            scheduleCommandEventClear(duration: 2.0)
        }
    }
    
    /// Format subcommand prompt with optional options list
    private func formatSubcommandPrompt(_ prompt: String?, options: [String]?) -> String {
        var result = prompt ?? ""
        
        // Append abbreviated options list if available
        if let opts = options, !opts.isEmpty {
            let abbrev = opts.prefix(3).joined(separator: "/")
            result += result.isEmpty ? "[\(abbrev)]" : " [\(abbrev)]"
        }
        
        return result
    }

    /// Process a raw keyboard/mouse event and update the display label
    /// (Only if no AutoCAD command event has occurred recently)
    private func processEvent(_ eventDescription: String) {
        lastEventTime = Date()
        
        // Priority rule: suppress keyboard updates if an AutoCAD command event occurred
        // within the last 500ms (prevents keyboard from overwriting clean command labels)
        if let lastDirect = lastDirectEventTime {
            let timeSinceDirectEvent = Date().timeIntervalSince(lastDirect)
            if timeSinceDirectEvent < 0.5 {
                // Still within suppression window — ignore keyboard event
                return
            }
        }
        
        // Safe to process keyboard event
        commandSource = .keyboard
        
        // Get the active profile
        guard let activeProfile = settingsStore.currentProfile ?? settingsStore.activeProfile() else {
            currentLabel = sanitizeEventDisplay(eventDescription)
            secondaryLabel = ""
            colorCategory = .default
            scheduleAutoClear()
            return
        }

        // Check for exact match in mappings
        if let mapping = activeProfile.mappings.first(where: { 
            normalizeEventDescription($0.trigger.eventDescription) == normalizeEventDescription(eventDescription)
        }) {
            currentLabel = mapping.label
            secondaryLabel = ""
            colorCategory = mapping.colorCategory
            scheduleAutoClear()
            return
        }

        // No match found — display sanitized raw event
        currentLabel = sanitizeEventDisplay(eventDescription)
        secondaryLabel = ""
        colorCategory = .default
        scheduleAutoClear()
    }

    /// Normalize event descriptions for comparison (case-insensitive, trim spaces)
    private func normalizeEventDescription(_ desc: String) -> String {
        return desc.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Sanitize event display for clean overlay rendering
    private func sanitizeEventDisplay(_ event: String) -> String {
        // Remove excessive whitespace
        let cleaned = event.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Limit to reasonable length for display
        if cleaned.count > 12 {
            return String(cleaned.prefix(12)) + "…"
        }
        return cleaned
    }
    
    // MARK: - Command Mapping & Categorization
    
    /// Map AutoCAD command name to display labels (abbreviation + full name)
    private func labelForCommand(_ name: String) -> (short: String, full: String) {
        let upper = name.uppercased()
        
        // Common AutoCAD commands with 1-3 char abbreviations
        let builtIn: [String: String] = [
            // Drawing commands
            "LINE": "LN",    "CIRCLE": "CI",    "ARC": "A",      "PLINE": "PL",
            "RECTANG": "RC", "POLYGON": "PG",   "ELLIPSE": "EL", "SPLINE": "SP",
            
            // Modification commands
            "OFFSET": "OF",  "TRIM": "TR",      "EXTEND": "EX",  "FILLET": "F",
            "CHAMFER": "CH", "MIRROR": "MI",    "ARRAY": "AR",   "COPY": "CO",
            "MOVE": "M",     "ROTATE": "RO",    "SCALE": "SC",   "STRETCH": "ST",
            "PEDIT": "PE",   "JOIN": "J",
            
            // Modification — Hatch & Pattern
            "HATCH": "H",    "BHATCH": "H",     "GRADIENT": "GR",
            
            // Deletion
            "ERASE": "E",    "EXPLODE": "X",    "DELETE": "DEL",
            
            // Navigation & View
            "ZOOM": "Z",     "PAN": "P",        "REGEN": "RE",   "REDRAW": "RD",
            "3DORBIT": "3D", "VIEW": "V",
            
            // Layer & Properties
            "LAYER": "LA",   "PROPERTIES": "PR","LAYMGR": "LM",   "LAYISO": "LI",
            
            // Block & Reference
            "BLOCK": "B",    "INSERT": "I",     "XREF": "XR",    "REFEDIT": "RF",
            
            // Text & Annotation
            "MTEXT": "MT",   "TEXT": "DT",      "DTEXT": "DT",   "SPELL": "SP",
            
            // Dimension
            "DIMLINEAR": "DL","DIMRADIUS": "DR","DIMANGULAR": "DA","DIMALIGNED": "DA",
            "DIMDIAMETER": "DD","DIMORDINATE": "DO",
            
            // File Operations
            "SAVE": "SA",    "SAVEAS": "SAS",   "QSAVE": "QS",   "PLOT": "PL",
            "EXPORT": "EXP", "PUBLISH": "PUB",  "OPEN": "OP",    "NEW": "NW",
            
            // Database operations
            "PURGE": "PU",   "WBLOCK": "WB",
        ]
        
        return (
            short: builtIn[upper] ?? String(upper.prefix(3)),
            full: upper
        )
    }
    
    /// Categorize AutoCAD command for color assignment
    private func colorForCommand(_ name: String) -> ColorCategory {
        let upper = name.uppercased()
        
        let drawingCommands = ["LINE", "CIRCLE", "ARC", "PLINE", "RECTANG", "POLYGON", "ELLIPSE", "SPLINE", "HATCH", "BHATCH", "GRADIENT"]
        let modifyCommands = ["OFFSET", "TRIM", "EXTEND", "FILLET", "CHAMFER", "MIRROR", "ARRAY", "COPY", "MOVE", "ROTATE", "SCALE", "STRETCH", "PEDIT", "JOIN", "EXPLODE"]
        let navigationCommands = ["PAN", "ZOOM", "REGEN", "REDRAW", "VIEW", "3DORBIT"]
        let destructiveCommands = ["ERASE", "PURGE", "WBLOCK", "DELETE"]
        let fileCommands = ["SAVE", "SAVEAS", "QSAVE", "PLOT", "EXPORT", "PUBLISH", "OPEN", "NEW"]
        let propertyCommands = ["LAYER", "PROPERTIES", "LAYMGR", "LAYISO", "BLOCK", "INSERT", "XREF", "REFEDIT"]
        
        if drawingCommands.contains(upper) {
            return .selection  // Drawing commands use selection color
        } else if modifyCommands.contains(upper) {
            return .edit       // Modification commands
        } else if navigationCommands.contains(upper) {
            return .navigation // Navigation commands
        } else if destructiveCommands.contains(upper) {
            return .destructive // Dangerous operations
        } else if fileCommands.contains(upper) {
            return .file       // File operations
        } else if propertyCommands.contains(upper) {
            return .edit       // Property/management operations
        } else {
            return .default    // Unknown command
        }
    }

    /// Schedule automatic clearing of the label after a short delay
    private func scheduleAutoClear() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.currentLabel = "Ready"
                self?.colorCategory = .default
            }
        }
    }

    /// Invalidate timer on deinit to avoid leaks
    deinit {
        displayTimer?.invalidate()
    }
}
