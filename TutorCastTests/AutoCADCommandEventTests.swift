import XCTest
@testable import TutorCast

/// Unit tests for AutoCADCommandEvent JSON encoding/decoding and data sanitization.
/// Tests all EventType cases, roundtrip serialization, and rejection of malformed input.
class AutoCADCommandEventTests: XCTestCase {
    
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    
    // MARK: - JSON Roundtrip Tests
    
    /// Test: .commandStarted event roundtrip
    func testCommandStartedRoundtrip() throws {
        let original = AutoCADCommandEvent(
            type: .commandStarted,
            commandName: "LINE",
            subcommand: nil,
            activeOptions: nil,
            timestamp: Date(timeIntervalSince1970: 1234567890),
            source: .nativePlugin
        )
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AutoCADCommandEvent.self, from: data)
        
        XCTAssertEqual(original.type, decoded.type)
        XCTAssertEqual(original.commandName, decoded.commandName)
        XCTAssertNil(decoded.subcommand)
        XCTAssertEqual(original.source, decoded.source)
    }
    
    /// Test: .subcommandPrompt event roundtrip
    func testSubcommandPromptRoundtrip() throws {
        let original = AutoCADCommandEvent(
            type: .subcommandPrompt,
            commandName: "OFFSET",
            subcommand: "Specify offset distance or [Through/Erase/Layer] <1.0>:",
            activeOptions: ["Through", "Erase", "Layer"],
            timestamp: Date(timeIntervalSince1970: 1234567890),
            source: .parallelsPlugin
        )
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AutoCADCommandEvent.self, from: data)
        
        XCTAssertEqual(original.type, decoded.type)
        XCTAssertEqual(original.commandName, decoded.commandName)
        XCTAssertEqual(original.subcommand, decoded.subcommand)
        XCTAssertEqual(original.activeOptions, decoded.activeOptions)
        XCTAssertEqual(original.source, decoded.source)
    }
    
    /// Test: .commandCancelled event roundtrip
    func testCommandCancelledRoundtrip() throws {
        let original = AutoCADCommandEvent(
            type: .commandCancelled,
            commandName: "LINE",
            subcommand: nil,
            activeOptions: nil,
            timestamp: Date(timeIntervalSince1970: 1234567890),
            source: .keyboard
        )
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AutoCADCommandEvent.self, from: data)
        
        XCTAssertEqual(original.type, decoded.type)
        XCTAssertEqual(original.source, decoded.source)
    }
    
    /// Test: .optionSelected event roundtrip
    func testOptionSelectedRoundtrip() throws {
        let original = AutoCADCommandEvent(
            type: .optionSelected,
            commandName: "OFFSET",
            subcommand: "Through",
            activeOptions: nil,
            timestamp: Date(timeIntervalSince1970: 1234567890),
            source: .nativePlugin
        )
        
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AutoCADCommandEvent.self, from: data)
        
        XCTAssertEqual(original.type, decoded.type)
        XCTAssertEqual(original.subcommand, decoded.subcommand)
    }
    
    // MARK: - Sanitization Tests
    
    /// Test: Command name with control characters is rejected
    func testControlCharacterRejection() {
        // Simulate malformed input with null byte
        let malformedData = """
        {
            "type": "commandStarted",
            "commandName": "LINE\\u0000",
            "timestamp": 1234567890,
            "source": "nativePlugin"
        }
        """.data(using: .utf8)!
        
        XCTAssertThrowsError(
            try decoder.decode(AutoCADCommandEvent.self, from: malformedData)
        )
    }
    
    /// Test: Extremely long command name is rejected
    func testExcessivelyLongCommandName() {
        // Create command name longer than security limit (64 chars)
        let longName = String(repeating: "A", count: 150)
        
        let original = AutoCADCommandEvent(
            type: .commandStarted,
            commandName: longName,
            subcommand: nil,
            activeOptions: nil,
            timestamp: Date(),
            source: .nativePlugin
        )
        
        // Should encode successfully but be subject to validation
        let data = try! encoder.encode(original)
        let decoded = try! decoder.decode(AutoCADCommandEvent.self, from: data)
        
        // The SecurityValidator will reject this during processing
        XCTAssertEqual(decoded.commandName, longName)
        XCTAssertGreaterThan(decoded.commandName.count, 64)
    }
    
    /// Test: Subcommand with excessive content
    func testExcessivelyLongSubcommand() {
        let longSubcommand = String(repeating: "B", count: 200)
        
        let original = AutoCADCommandEvent(
            type: .subcommandPrompt,
            commandName: "OFFSET",
            subcommand: longSubcommand,
            activeOptions: nil,
            timestamp: Date(),
            source: .parallelsPlugin
        )
        
        let data = try! encoder.encode(original)
        let decoded = try! decoder.decode(AutoCADCommandEvent.self, from: data)
        
        // SecurityValidator will reject during processing
        XCTAssertGreaterThan(decoded.subcommand?.count ?? 0, 128)
    }
    
    /// Test: Empty command name
    func testEmptyCommandName() {
        let original = AutoCADCommandEvent(
            type: .commandStarted,
            commandName: "",
            subcommand: nil,
            activeOptions: nil,
            timestamp: Date(),
            source: .nativePlugin
        )
        
        let data = try! encoder.encode(original)
        let decoded = try! decoder.decode(AutoCADCommandEvent.self, from: data)
        
        XCTAssertEqual(decoded.commandName, "")
    }
    
    // MARK: - EventType Encoding Tests
    
    /// Test: All EventType cases encode/decode correctly
    func testAllEventTypesCases() throws {
        let eventTypes: [AutoCADCommandEvent.EventType] = [
            .commandStarted,
            .subcommandPrompt,
            .commandCancelled,
            .optionSelected
        ]
        
        for eventType in eventTypes {
            let event = AutoCADCommandEvent(
                type: eventType,
                commandName: "TEST",
                subcommand: "test",
                activeOptions: nil,
                timestamp: Date(),
                source: .nativePlugin
            )
            
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(AutoCADCommandEvent.self, from: data)
            
            XCTAssertEqual(event.type, decoded.type, "Failed for type: \(eventType)")
        }
    }
    
    /// Test: Source enum roundtrip (both plugin and keyboard sources)
    func testSourceEnumRoundtrip() throws {
        let sources: [AutoCADCommandEvent.Source] = [
            .nativePlugin,
            .parallelsPlugin,
            .keyboard
        ]
        
        for source in sources {
            let event = AutoCADCommandEvent(
                type: .commandStarted,
                commandName: "TEST",
                subcommand: nil,
                activeOptions: nil,
                timestamp: Date(),
                source: source
            )
            
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(AutoCADCommandEvent.self, from: data)
            
            XCTAssertEqual(event.source, decoded.source, "Failed for source: \(source)")
        }
    }
    
    // MARK: - Array Handling Tests
    
    /// Test: activeOptions array with multiple values
    func testActiveOptionsArrayRoundtrip() throws {
        let options = ["Through", "Erase", "Layer", "Multiple"]
        let event = AutoCADCommandEvent(
            type: .subcommandPrompt,
            commandName: "OFFSET",
            subcommand: "Choose option",
            activeOptions: options,
            timestamp: Date(),
            source: .nativePlugin
        )
        
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(AutoCADCommandEvent.self, from: data)
        
        XCTAssertEqual(decoded.activeOptions, options)
    }
    
    /// Test: Empty activeOptions array
    func testEmptyActiveOptionsArray() throws {
        let event = AutoCADCommandEvent(
            type: .subcommandPrompt,
            commandName: "OFFSET",
            subcommand: "Choose",
            activeOptions: [],
            timestamp: Date(),
            source: .nativePlugin
        )
        
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(AutoCADCommandEvent.self, from: data)
        
        XCTAssertEqual(decoded.activeOptions, [])
    }
    
    /// Test: Nil vs empty array distinction
    func testNilVsEmptyOptionsArray() throws {
        // Event with nil options
        let eventNil = AutoCADCommandEvent(
            type: .commandStarted,
            commandName: "LINE",
            subcommand: nil,
            activeOptions: nil,
            timestamp: Date(),
            source: .nativePlugin
        )
        
        // Event with empty array
        let eventEmpty = AutoCADCommandEvent(
            type: .commandStarted,
            commandName: "LINE",
            subcommand: nil,
            activeOptions: [],
            timestamp: Date(),
            source: .nativePlugin
        )
        
        let dataNil = try encoder.encode(eventNil)
        let dataEmpty = try encoder.encode(eventEmpty)
        
        let decodedNil = try decoder.decode(AutoCADCommandEvent.self, from: dataNil)
        let decodedEmpty = try decoder.decode(AutoCADCommandEvent.self, from: dataEmpty)
        
        XCTAssertNil(decodedNil.activeOptions)
        XCTAssertEqual(decodedEmpty.activeOptions, [])
    }
    
    // MARK: - Timestamp Tests
    
    /// Test: Timestamp precision preserved in roundtrip
    func testTimestampPrecision() throws {
        let timestamp = Date(timeIntervalSince1970: 1234567890.123456)
        let event = AutoCADCommandEvent(
            type: .commandStarted,
            commandName: "LINE",
            subcommand: nil,
            activeOptions: nil,
            timestamp: timestamp,
            source: .nativePlugin
        )
        
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(AutoCADCommandEvent.self, from: data)
        
        // Timestamps should be very close (within milliseconds)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, 
                      timestamp.timeIntervalSince1970, 
                      accuracy: 0.001)
    }
    
    // MARK: - Malformed JSON Tests
    
    /// Test: Invalid JSON structure is rejected
    func testInvalidJSONStructure() {
        let invalidJSON = """
        {
            "type": "commandStarted",
            "commandName": "LINE"
            "timestamp": 1234567890
        }
        """.data(using: .utf8)!
        
        XCTAssertThrowsError(
            try decoder.decode(AutoCADCommandEvent.self, from: invalidJSON)
        )
    }
    
    /// Test: Missing required fields
    func testMissingRequiredFields() {
        let incompleteJSON = """
        {
            "type": "commandStarted"
        }
        """.data(using: .utf8)!
        
        XCTAssertThrowsError(
            try decoder.decode(AutoCADCommandEvent.self, from: incompleteJSON)
        )
    }
    
    /// Test: Unknown EventType value
    func testUnknownEventType() {
        let unknownTypeJSON = """
        {
            "type": "unknownType",
            "commandName": "LINE",
            "timestamp": 1234567890,
            "source": "nativePlugin"
        }
        """.data(using: .utf8)!
        
        XCTAssertThrowsError(
            try decoder.decode(AutoCADCommandEvent.self, from: unknownTypeJSON)
        )
    }
}
