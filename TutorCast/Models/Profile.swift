import Foundation

// MARK: - Input Validation

/// Sanitizes string input by removing potentially dangerous characters
private func sanitizeString(_ input: String, maxLength: Int = 512) -> String {
    // Trim whitespace and enforce maximum length
    var sanitized = input.trimmingCharacters(in: .whitespaces).prefix(maxLength)
    
    // Remove control characters and other potentially dangerous sequences
    let controlCharacters = CharacterSet.controlCharacters.union(CharacterSet.illegalCharacters)
    sanitized = sanitized.filter { !controlCharacters.contains($0.unicodeScalars.first!) }
    
    return String(sanitized)
}

// MARK: - Color Categories

/// Defines visual categories for action shortcuts in the overlay
public enum ColorCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case `default` = "default"
    case navigation = "navigation"
    case zoom = "zoom"
    case selection = "selection"
    case edit = "edit"
    case destructive = "destructive"
    case file = "file"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .default: return "Default"
        case .navigation: return "Navigation (Orange)"
        case .zoom: return "Zoom (Cyan)"
        case .selection: return "Selection (Green)"
        case .edit: return "Edit (Blue)"
        case .destructive: return "Destructive (Red)"
        case .file: return "File (Purple)"
        }
    }
    
    public var color: (red: Double, green: Double, blue: Double) {
        switch self {
        case .default: return (0.95, 0.95, 0.95)
        case .navigation: return (1.0, 0.6, 0.0)
        case .zoom: return (0.0, 1.0, 1.0)
        case .selection: return (0.0, 1.0, 0.0)
        case .edit: return (0.4, 0.7, 1.0)
        case .destructive: return (1.0, 0.2, 0.2)
        case .file: return (0.8, 0.4, 1.0)
        }
    }
}

// MARK: - Action Trigger

/// Represents a keyboard/mouse action that can trigger a label display
public struct ActionTrigger: Codable, Identifiable, Hashable {
    public var id: UUID
    public var eventDescription: String  // e.g., "Middle Drag", "⌘ + Z", "Left Click", "Scroll Up"
    
    public init(id: UUID = UUID(), eventDescription: String) {
        self.id = id
        self.eventDescription = sanitizeString(eventDescription, maxLength: 256)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        let rawEvent = try container.decode(String.self, forKey: .eventDescription)
        self.eventDescription = sanitizeString(rawEvent, maxLength: 256)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, eventDescription
    }
}

// MARK: - Action Mapping

public struct ActionMapping: Codable, Identifiable, Hashable {
    public var id: UUID
    public var trigger: ActionTrigger
    public var label: String  // Display label: 1-8 chars recommended, 1-3 best
    public var colorCategory: ColorCategory

    public init(
        id: UUID = UUID(),
        trigger: ActionTrigger,
        label: String,
        colorCategory: ColorCategory = .default
    ) {
        self.id = id
        self.trigger = trigger
        self.label = sanitizeString(label, maxLength: 8)
        self.colorCategory = colorCategory
    }
    
    /// Convenience initializer for migration from old action/label format
    public init(
        id: UUID = UUID(),
        action: String,
        label: String,
        colorCategory: ColorCategory = .default
    ) {
        self.id = id
        self.trigger = ActionTrigger(eventDescription: action)
        self.label = sanitizeString(label, maxLength: 8)
        self.colorCategory = colorCategory
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        
        // Support both old format (action: String) and new format (trigger: ActionTrigger)
        if let trigger = try? container.decode(ActionTrigger.self, forKey: .trigger) {
            self.trigger = trigger
        } else if let actionStr = try? container.decode(String.self, forKey: .action) {
            self.trigger = ActionTrigger(eventDescription: actionStr)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Neither trigger nor action present"
                )
            )
        }
        
        let rawLabel = try container.decode(String.self, forKey: .label)
        self.label = sanitizeString(rawLabel, maxLength: 8)
        
        let categoryRaw = try container.decode(String.self, forKey: .colorCategory)
        self.colorCategory = ColorCategory(rawValue: categoryRaw) ?? .default
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(trigger, forKey: .trigger)
        try container.encode(label, forKey: .label)
        try container.encode(colorCategory.rawValue, forKey: .colorCategory)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, trigger, action, label, colorCategory
    }
}

// MARK: - Profile

public struct Profile: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var mappings: [ActionMapping]
    public var isCustom: Bool  // false for built-in profiles, true for user-created

    public init(
        id: UUID = UUID(),
        name: String,
        mappings: [ActionMapping] = [],
        isCustom: Bool = true
    ) {
        self.id = id
        self.name = sanitizeString(name, maxLength: 128)
        self.mappings = mappings
        self.isCustom = isCustom
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        let rawName = try container.decode(String.self, forKey: .name)
        self.name = sanitizeString(rawName, maxLength: 128)
        self.mappings = try container.decode([ActionMapping].self, forKey: .mappings)
        self.isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? true
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, mappings, isCustom
    }
}

// MARK: - Built-in Profiles

public enum BuiltInProfiles {
    public static func autoCAD() -> Profile {
        let items: [ActionMapping] = [
            // Mouse/Navigation — Primary interactions (Orange)
            .init(
                trigger: ActionTrigger(eventDescription: "Middle Drag"),
                label: "Pn",
                colorCategory: .navigation
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "Left Click"),
                label: "Sel",
                colorCategory: .selection
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "Right Click"),
                label: "Mnu",
                colorCategory: .default
            ),
            
            // Zoom Operations (Cyan)
            .init(
                trigger: ActionTrigger(eventDescription: "Scroll Up"),
                label: "Z+",
                colorCategory: .zoom
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "Scroll Down"),
                label: "Z-",
                colorCategory: .zoom
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "Z"),
                label: "Zm",
                colorCategory: .zoom
            ),
            
            // Edit Operations (Blue)
            .init(
                trigger: ActionTrigger(eventDescription: "⌘Z"),
                label: "U",
                colorCategory: .edit
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "⌘⇧Z"),
                label: "R",
                colorCategory: .edit
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "E"),
                label: "Er",
                colorCategory: .edit
            ),
            
            // Destructive (Red)
            .init(
                trigger: ActionTrigger(eventDescription: "Delete"),
                label: "Del",
                colorCategory: .destructive
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "X"),
                label: "Cut",
                colorCategory: .destructive
            ),
            
            // File Operations (Purple)
            .init(
                trigger: ActionTrigger(eventDescription: "⌘S"),
                label: "S",
                colorCategory: .file
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "⌘N"),
                label: "New",
                colorCategory: .file
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "⌘O"),
                label: "O",
                colorCategory: .file
            ),
            
            // Draw Commands
            .init(
                trigger: ActionTrigger(eventDescription: "L"),
                label: "L",
                colorCategory: .default
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "C"),
                label: "C",
                colorCategory: .default
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "A"),
                label: "A",
                colorCategory: .default
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "R"),
                label: "Rc",
                colorCategory: .default
            ),
            
            // General Shortcuts
            .init(
                trigger: ActionTrigger(eventDescription: "Escape"),
                label: "Esc",
                colorCategory: .default
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "⌘D"),
                label: "Dup",
                colorCategory: .edit
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "⌘G"),
                label: "Grp",
                colorCategory: .default
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "⌘⌫"),
                label: "Clr",
                colorCategory: .default
            ),
        ]
        return Profile(
            name: "AutoCAD",
            mappings: items,
            isCustom: false
        )
    }
    
    public static func photoshop() -> Profile {
        let items: [ActionMapping] = [
            .init(
                trigger: ActionTrigger(eventDescription: "B"),
                label: "Br",
                colorCategory: .edit
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "E"),
                label: "Er",
                colorCategory: .edit
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "V"),
                label: "Mv",
                colorCategory: .default
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "M"),
                label: "Sel",
                colorCategory: .selection
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "⌘Z"),
                label: "U",
                colorCategory: .edit
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "Space"),
                label: "Pn",
                colorCategory: .navigation
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "⌘+"),
                label: "Z+",
                colorCategory: .zoom
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "⌘-"),
                label: "Z-",
                colorCategory: .zoom
            ),
        ]
        return Profile(
            name: "Photoshop",
            mappings: items,
            isCustom: false
        )
    }
    
    public static func `default`() -> Profile {
        let items: [ActionMapping] = [
            .init(
                trigger: ActionTrigger(eventDescription: "Left Click"),
                label: "Clk",
                colorCategory: .selection
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "Right Click"),
                label: "Mnu",
                colorCategory: .default
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "Scroll Up"),
                label: "↑",
                colorCategory: .default
            ),
            .init(
                trigger: ActionTrigger(eventDescription: "Scroll Down"),
                label: "↓",
                colorCategory: .default
            ),
        ]
        return Profile(
            name: "Default",
            mappings: items,
            isCustom: false
        )
    }
}
