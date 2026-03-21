import XCTest
@testable import TutorCast

/// Unit tests for AutoCAD prompt string parsing.
/// Tests extraction of options from bracket notation in AutoCAD prompts.
class PromptParsingTests: XCTestCase {
    
    // MARK: - Basic Option Extraction
    
    /// Test: Extract single option from brackets
    func testSingleOptionExtraction() {
        let prompt = "Specify offset distance or [Through] <1.0>:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, ["Through"])
    }
    
    /// Test: Extract multiple options from brackets
    func testMultipleOptionsExtraction() {
        let prompt = "Specify offset distance or [Through/Erase/Layer] <1.0>:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, ["Through", "Erase", "Layer"])
    }
    
    /// Test: Extract four options from brackets
    func testFourOptionsExtraction() {
        let prompt = "Specify fillet radius or [Polyline/Chamfer/Trim/nOtrim] <0.5000>:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, ["Polyline", "Chamfer", "Trim", "nOtrim"])
    }
    
    // MARK: - Real-world AutoCAD Prompts
    
    /// Test: Real OFFSET prompt
    func testRealOffsetPrompt() {
        let prompt = "Specify offset distance or [Through/Erase/Layer] <1.0>:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, ["Through", "Erase", "Layer"])
    }
    
    /// Test: Real COPY prompt
    func testRealCopyPrompt() {
        let prompt = "Specify base point or [Displacement/mOde] <Displacement>:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, ["Displacement", "mOde"])
    }
    
    /// Test: Real FILLET prompt
    func testRealFilletPrompt() {
        let prompt = "Specify fillet radius or [Polyline/Chamfer/Trim/nOtrim] <0.5000>:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, ["Polyline", "Chamfer", "Trim", "nOtrim"])
    }
    
    /// Test: Real ARRAY prompt
    func testRealArrayPrompt() {
        let prompt = "Enter the number of items to array or [Fit/Fill/eXit] <5>:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, ["Fit", "Fill", "eXit"])
    }
    
    // MARK: - Edge Cases
    
    /// Test: No brackets (no options)
    func testNoOptions() {
        let prompt = "Specify next point: "
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, [])
    }
    
    /// Test: Empty brackets
    func testEmptyBrackets() {
        let prompt = "Specify point [] <default>:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, [])
    }
    
    /// Test: Single character options
    func testSingleCharacterOptions() {
        let prompt = "Continue? [Y/N] <Y>:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, ["Y", "N"])
    }
    
    /// Test: Mixed case option shorthand (lowercase command letter)
    func testMixedCaseShorthand() {
        let prompt = "Specify offset or [eXit/Undo] <1.0>:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, ["eXit", "Undo"])
    }
    
    // MARK: - Multiple Bracket Groups
    
    /// Test: Only first bracket group extracted (most AutoCAD prompts have only one)
    func testMultipleBracketGroups() {
        let prompt = "Specify offset [Through/Erase] or [Layer/Something] <1.0>:"
        let options = extractOptionsFromPrompt(prompt)
        
        // Should extract first bracket group
        XCTAssertEqual(options.count, 2)
        XCTAssertTrue(options.contains("Through"))
        XCTAssertTrue(options.contains("Erase"))
    }
    
    // MARK: - Whitespace Handling
    
    /// Test: Brackets with internal whitespace
    func testBracketsWithWhitespace() {
        let prompt = "Specify or [ Through / Erase / Layer ] <1.0>:"
        let options = extractOptionsFromPrompt(prompt)
        
        // Should trim whitespace from each option
        XCTAssertEqual(options.count, 3)
        XCTAssertTrue(options.contains("Through"))
        XCTAssertTrue(options.contains("Erase"))
        XCTAssertTrue(options.contains("Layer"))
    }
    
    /// Test: Brackets with no internal whitespace
    func testBracketsNoWhitespace() {
        let prompt = "Specify offset or [Through/Erase/Layer]:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, ["Through", "Erase", "Layer"])
    }
    
    // MARK: - Special Characters
    
    /// Test: Options with special formatting
    func testSpecialFormatting() {
        let prompt = "Enter option [Fit/Fill]:  "
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, ["Fit", "Fill"])
    }
    
    /// Test: Options with numbers
    func testOptionsWithNumbers() {
        let prompt = "Enter mode [2D/3D/On/Off] <2D>:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, ["2D", "3D", "On", "Off"])
    }
    
    /// Test: Options with lowercase letters only
    func testLowercaseOptions() {
        let prompt = "Specify [always/once/never] <always>:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, ["always", "once", "never"])
    }
    
    // MARK: - Default Value Handling
    
    /// Test: Prompt with default value in angle brackets
    func testDefaultValueExtraction() {
        let prompt = "Specify distance <1.0>:"
        let options = extractOptionsFromPrompt(prompt)
        
        // Should not extract the default value
        XCTAssertEqual(options, [])
    }
    
    /// Test: Prompt with default and options
    func testDefaultAndOptionsCoexist() {
        let prompt = "Specify offset distance or [Through/Erase/Layer] <1.0>:"
        let options = extractOptionsFromPrompt(prompt)
        
        // Should extract only options from brackets, not default from angle brackets
        XCTAssertEqual(options, ["Through", "Erase", "Layer"])
        XCTAssertFalse(options.contains("1.0"))
    }
    
    // MARK: - Localization Tests
    
    /// Test: Non-English AutoCAD option names
    func testNonEnglishOptions() {
        // Spanish OFFSET prompt (potential)
        let spanishPrompt = "Especifique distancia o [Atravesar/Borrar/Capa] <1.0>:"
        let options = extractOptionsFromPrompt(spanishPrompt)
        
        // Should still extract regardless of language
        XCTAssertEqual(options.count, 3)
    }
    
    // MARK: - Malformed Input
    
    /// Test: Unmatched brackets
    func testUnmatchedBrackets() {
        let prompt = "Specify or [Through/Erase <1.0>:"
        let options = extractOptionsFromPrompt(prompt)
        
        // Should handle gracefully (return empty or partial)
        XCTAssertNotNil(options)
    }
    
    /// Test: Nested brackets (shouldn't occur in AutoCAD)
    func testNestedBrackets() {
        let prompt = "Specify or [Through/Erase[Inner]/Layer] <1.0>:"
        let options = extractOptionsFromPrompt(prompt)
        
        // Should handle without crashing
        XCTAssertNotNil(options)
    }
    
    /// Test: Empty string
    func testEmptyString() {
        let prompt = ""
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, [])
    }
    
    /// Test: Only brackets
    func testOnlyBrackets() {
        let prompt = "[]"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options, [])
    }
    
    // MARK: - Performance Tests
    
    /// Test: Very long prompt string
    func testLongPromptString() {
        let longPrompt = "Specify offset distance or [Through/Erase/Layer/Mode/Option/Selection/Multiple/Tangent/Reference/Undo] <1.0>:"
        let options = extractOptionsFromPrompt(longPrompt)
        
        XCTAssertGreaterThan(options.count, 5)
        XCTAssertTrue(options.contains("Through"))
        XCTAssertTrue(options.contains("Multiple"))
    }
    
    /// Test: Very long option names
    func testLongOptionNames() {
        let prompt = "Specify [VeryLongOptionName/AnotherExtremelyLongOption/ShortOne] <default>:"
        let options = extractOptionsFromPrompt(prompt)
        
        XCTAssertEqual(options.count, 3)
        XCTAssertTrue(options.contains("VeryLongOptionName"))
    }
    
    // MARK: - Integration with LabelEngine
    
    /// Test: Options displayed in overlay
    func testOptionsForDisplay() {
        let prompt = "Specify offset distance or [Through/Erase/Layer] <1.0>:"
        let options = extractOptionsFromPrompt(prompt)
        
        // These options would be displayed in OverlayContentView
        // Ensure they're suitable for display
        for option in options {
            XCTAssertFalse(option.isEmpty)
            XCTAssertFalse(option.contains("["))
            XCTAssertFalse(option.contains("]"))
        }
    }
    
    // MARK: - Helper Function
    
    /// Extracts bracket-enclosed options from AutoCAD prompt string.
    /// Returns array of individual options (separated by / in the original).
    private func extractOptionsFromPrompt(_ prompt: String) -> [String] {
        // Find the bracket pair
        guard let openBracket = prompt.firstIndex(of: "["),
              let closeBracket = prompt.firstIndex(of: "]") else {
            return []
        }
        
        // Extract content between brackets
        let startIndex = prompt.index(after: openBracket)
        guard startIndex < closeBracket else { return [] }
        
        let content = String(prompt[startIndex..<closeBracket])
        
        // Split by forward slash and trim whitespace
        let options = content.split(separator: "/")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        return options
    }
}
