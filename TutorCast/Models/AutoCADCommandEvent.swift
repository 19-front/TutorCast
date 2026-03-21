// AutoCADCommandEvent.swift
// Unified command event model used by both plugin scenarios (native macOS and Parallels Windows)
// before transmission to LabelEngine.

import Foundation

/// Unified data model for AutoCAD command events
/// Represents a single command state change or prompt update
struct AutoCADCommandEvent: Codable {
    /// Type of event occurring
    enum EventType: String, Codable {
        case commandStarted      // A top-level command began (e.g., LINE, OFFSET)
        case subcommandPrompt    // A subcommand/option prompt is active (e.g., "Specify first point:")
        case optionSelected      // User picked an option (e.g., "Through" from OFFSET)
        case commandCompleted    // Command finished successfully
        case commandCancelled    // ESC or error cancelled the command
        case commandLineText     // Raw command line text (fallback)
    }
    
    /// Source plugin that generated this event
    enum EventSource: String, Codable {
        case nativePlugin        // From AutoCAD for macOS plugin (Python/LISP)
        case parallelsPlugin     // From Windows VM plugin via socket IPC
        case keyboardInference   // Fallback: derived from keyboard events
    }
    
    /// Event type
    var type: EventType
    
    /// Command name in uppercase (e.g., "LINE", "OFFSET", "HATCH")
    var commandName: String
    
    /// Subcommand or prompt text (e.g., "Specify first point:", "Erase existing offset")
    /// nil if not applicable to this event type
    var subcommand: String?
    
    /// Available options at current prompt (e.g., ["Through", "Erase", "Layer"])
    /// Extracted from option brackets in AutoCAD command line
    /// nil if not applicable
    var activeOptions: [String]?
    
    /// Option the user just selected (e.g., "Through")
    /// Only populated for optionSelected events
    var selectedOption: String?
    
    /// Raw command line text as fallback (e.g., "Command: LINE Specify first point: [Through/Erase/Layer]")
    /// Useful if structured parsing fails
    var rawCommandLineText: String?
    
    /// When this event occurred (ISO 8601 UTC)
    var timestamp: Date
    
    /// Which plugin/source generated this event
    var source: EventSource
    
    // MARK: - Codable Customization
    
    enum CodingKeys: String, CodingKey {
        case type
        case commandName
        case subcommand
        case activeOptions
        case selectedOption
        case rawCommandLineText
        case timestamp
        case source
    }
    
    /// Custom decoder to handle ISO 8601 timestamps
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        type = try container.decode(EventType.self, forKey: .type)
        commandName = try container.decode(String.self, forKey: .commandName)
        subcommand = try container.decodeIfPresent(String.self, forKey: .subcommand)
        activeOptions = try container.decodeIfPresent([String].self, forKey: .activeOptions)
        selectedOption = try container.decodeIfPresent(String.self, forKey: .selectedOption)
        rawCommandLineText = try container.decodeIfPresent(String.self, forKey: .rawCommandLineText)
        source = try container.decode(EventSource.self, forKey: .source)
        
        // Decode timestamp from ISO 8601 string
        let timestampString = try container.decode(String.self, forKey: .timestamp)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsedDate = formatter.date(from: timestampString) {
            timestamp = parsedDate
        } else {
            // Fallback: try without fractional seconds
            let fallbackFormatter = ISO8601DateFormatter()
            if let fallbackDate = fallbackFormatter.date(from: timestampString) {
                timestamp = fallbackDate
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .timestamp,
                    in: container,
                    debugDescription: "Invalid ISO 8601 timestamp: \(timestampString)"
                )
            }
        }
    }
    
    /// Custom encoder to handle ISO 8601 timestamps
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(type, forKey: .type)
        try container.encode(commandName, forKey: .commandName)
        try container.encodeIfPresent(subcommand, forKey: .subcommand)
        try container.encodeIfPresent(activeOptions, forKey: .activeOptions)
        try container.encodeIfPresent(selectedOption, forKey: .selectedOption)
        try container.encodeIfPresent(rawCommandLineText, forKey: .rawCommandLineText)
        try container.encode(source, forKey: .source)
        
        // Encode timestamp as ISO 8601 string
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestampString = formatter.string(from: timestamp)
        try container.encode(timestampString, forKey: .timestamp)
    }
    
    // MARK: - Initializers
    
    /// Initialize a command event
    init(
        type: EventType,
        commandName: String,
        subcommand: String? = nil,
        activeOptions: [String]? = nil,
        selectedOption: String? = nil,
        rawCommandLineText: String? = nil,
        timestamp: Date = Date(),
        source: EventSource
    ) {
        self.type = type
        self.commandName = commandName.uppercased()
        self.subcommand = subcommand
        self.activeOptions = activeOptions
        self.selectedOption = selectedOption
        self.rawCommandLineText = rawCommandLineText
        self.timestamp = timestamp
        self.source = source
    }
    
    // MARK: - Helpers
    
    /// Create a JSON string representation (newline-delimited for streaming)
    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
    
    /// Parse a newline-delimited JSON string
    static func fromJSONString(_ jsonString: String) -> AutoCADCommandEvent? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AutoCADCommandEvent.self, from: data)
    }
}
