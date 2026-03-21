// NativeMacOSAutoCADReader.swift
// TutorCast
//
// Reads the active command and subcommand from native AutoCAD for macOS
// using the Accessibility API (UIElement inspection).
//
// Strategy:
//   1. Locate the AutoCAD application via NSWorkspace or direct process lookup
//   2. Use AXUIElementCreateApplication to get the root accessibility element
//   3. Traverse the hierarchy to find the command line window / text field
//   4. Extract command name and subcommand text via AXValue attribute
//   5. Parse the text to separate command from prompt
//
// Command line layout in AutoCAD for macOS:
//   • A dedicated Command window or text field that shows:
//     - Current command name (if active)
//     - Current prompt or subcommand
//     - Command history
//
// Implementation note:
//   The Accessibility API on macOS requires the host application to have
//   Accessibility permissions granted by the user. This is enforced via
//   TCC and checked at runtime. See Info.plist and TutorCast.entitlements.

import AppKit
import Foundation

@MainActor
final class NativeMacOSAutoCADReader: NSObject, AutoCADReader {
    
    // MARK: - Private State
    
    private var autoCADApp: NSRunningApplication?
    private var axApp: AXUIElement?
    
    // Cache of common element identifiers to speed up repeated reads
    private var cachedCommandElement: AXUIElement?
    private var lastElementRefreshTime: Date = .distantPast
    private let elementRefreshInterval: TimeInterval = 5.0  // Refresh cache every 5 seconds
    
    override init() {
        super.init()
    }
    
    // MARK: - AutoCADReader Protocol
    
    func isAutoCADRunning() async -> Bool {
        // Search for running AutoCAD application
        let runningApps = NSWorkspace.shared.runningApplications
        let autoCADApp = runningApps.first { app in
            // Common bundle identifiers for AutoCAD on macOS
            let bundleID = app.bundleIdentifier ?? ""
            return bundleID.lowercased().contains("autocad") ||
                   (app.localizedName?.lowercased().contains("autocad") ?? false)
        }
        
        guard let autoCADApp else {
            self.autoCADApp = nil
            self.axApp = nil
            return false
        }
        
        self.autoCADApp = autoCADApp
        
        // Initialize AX element for the AutoCAD app
        let axElement = AXUIElementCreateApplication(autoCADApp.processIdentifier)
        self.axApp = axElement
        
        return true
    }
    
    func readCommandState() async throws -> AutoCADCommandState {
        guard let autoCADApp, autoCADApp.isRunning else {
            throw AutoCADReaderError.autoCADNotRunning
        }
        
        guard let axApp else {
            throw AutoCADReaderError.accessibilityElementNotFound
        }
        
        // Refresh cached element if needed
        if Date().timeIntervalSince(lastElementRefreshTime) > elementRefreshInterval {
            cachedCommandElement = nil
            lastElementRefreshTime = Date()
        }
        
        // Try to find the command line window
        let commandElement = try findCommandLineElement(in: axApp)
        cachedCommandElement = commandElement
        
        // Extract text from the command element
        let rawText = try extractText(from: commandElement)
        
        // Parse the raw text to separate command and subcommand
        let (commandName, subcommandText) = parseCommandLineText(rawText)
        
        return AutoCADCommandState(
            commandName: commandName,
            subcommandText: subcommandText
        )
    }
    
    // MARK: - AX Element Navigation
    
    /// Find the command line window/text field in the AutoCAD window hierarchy
    private func findCommandLineElement(in appElement: AXUIElement) throws -> AXUIElement {
        // Try to use cached element if available
        if let cached = cachedCommandElement {
            // Verify it's still valid by checking if it responds to AXValue
            var value: AnyObject?
            let getValueResult = AXUIElementCopyAttributeValue(cached, kAXValueAttribute as CFString, &value)
            if getValueResult == .success {
                return cached
            }
        }
        
        // Search strategy: traverse the window hierarchy looking for:
        // 1. A window with title containing "Command"
        // 2. A text field or text area with the command content
        // 3. A read-only text element with recent command history
        
        let windows = try getWindowsFromApp(appElement)
        
        for window in windows {
            // Check if this window is the command window
            if let element = try findCommandElementInWindow(window) {
                return element
            }
        }
        
        // Fallback: search for any read-only text area with significant content
        if let element = try findCommandElementByRole(appElement, role: kAXTextAreaRole) {
            return element
        }
        
        throw AutoCADReaderError.commandLineWindowNotFound
    }
    
    /// Get all windows from the application
    private func getWindowsFromApp(_ appElement: AXUIElement) throws -> [AXUIElement] {
        var windows: [AXUIElement] = []
        var windowsRef: AnyObject?
        
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        )
        
        guard result == .success, let windowArray = windowsRef as? [AXUIElement] else {
            return []
        }
        
        return windowArray
    }
    
    /// Find command element within a specific window
    private func findCommandElementInWindow(_ window: AXUIElement) throws -> AXUIElement? {
        // Check window title
        var titleRef: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        
        if let title = titleRef as? String {
            let lowerTitle = title.lowercased()
            if lowerTitle.contains("command") {
                // This is likely the command window; find the text element in it
                return try findTextElementInWindow(window)
            }
        }
        
        // Also check in case it's a dockable palette or other container
        return nil
    }
    
    /// Find text element within a window
    private func findTextElementInWindow(_ window: AXUIElement) throws -> AXUIElement? {
        var childrenRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            window,
            kAXChildrenAttribute as CFString,
            &childrenRef
        )
        
        guard result == .success, let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        
        for child in children {
            // Check if this child is a text area or text field
            var roleRef: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            
            if let role = roleRef as? String {
                if role == kAXTextAreaRole || role == kAXTextFieldRole {
                    return child
                }
            }
            
            // Recursively search children
            if let found = try findTextElementInWindow(child) {
                return found
            }
        }
        
        return nil
    }
    
    /// Find command element by role (fallback strategy)
    private func findCommandElementByRole(_ element: AXUIElement, role: String) throws -> AXUIElement? {
        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        
        if let elementRole = roleRef as? String, elementRole == role {
            return element
        }
        
        // Recursively search children
        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success else {
            return nil
        }
        
        guard let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        
        for child in children {
            if let found = try findCommandElementByRole(child, role: role) {
                return found
            }
        }
        
        return nil
    }
    
    // MARK: - Text Extraction
    
    /// Extract text content from an AX element
    private func extractText(from element: AXUIElement) throws -> String {
        var value: AnyObject?
        
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )
        
        guard result == .success else {
            throw AutoCADReaderError.cannotReadValue
        }
        
        if let text = value as? String {
            return text
        }
        
        // Try AXSelectedTextAttribute if AXValue is empty
        var selectedText: AnyObject?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        ) == .success, let text = selectedText as? String, !text.isEmpty {
            return text
        }
        
        return ""
    }
    
    // MARK: - Command Line Parsing
    
    /// Parse the raw command line text to extract command name and subcommand
    ///
    /// AutoCAD command line format examples:
    ///   "LINE" (command active, awaiting first point)
    ///   "Specify first point:" (prompt)
    ///   "OFFSET\nSpecify offset distance or [Through/Erase/Layer]:" (command + prompt)
    ///   "LINE\nSpecify first point:" (command + prompt)
    ///   "> LINE" (command with prompt indicator)
    ///   "Recent command: LINE" (command history)
    ///
    private func parseCommandLineText(_ text: String) -> (command: String, subcommand: String) {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        
        guard !lines.isEmpty else {
            return ("", "")
        }
        
        var commandName = ""
        var subcommandText = ""
        
        // Pattern 1: First non-empty line is likely the command
        // Pattern 2: Look for all-caps words (typical of AutoCAD commands)
        for (index, line) in lines.enumerated() {
            if line.isEmpty {
                continue
            }
            
            // Remove prompt indicators
            let cleanedLine = line
                .trimmingCharacters(in: CharacterSet(charactersIn: ">_"))
                .trimmingCharacters(in: .whitespaces)
            
            // Check if this looks like a command (all uppercase, 3-10 chars, no spaces)
            if isLikelyCommand(cleanedLine) && commandName.isEmpty {
                commandName = cleanedLine
                // Next line(s) are likely subcommands
                if index + 1 < lines.count {
                    subcommandText = lines[index + 1...].joined(separator: " ")
                }
                break
            } else if commandName.isEmpty {
                // This might be a prompt/subcommand before the command name
                // Check if we can extract command from prompt
                if let extracted = extractCommandFromPrompt(cleanedLine) {
                    commandName = extracted
                    subcommandText = cleanedLine
                    break
                } else {
                    // This is the subcommand/prompt
                    subcommandText = cleanedLine
                }
            }
        }
        
        // Trim subcommand to reasonable length
        if subcommandText.count > 80 {
            subcommandText = String(subcommandText.prefix(80)) + "…"
        }
        
        return (commandName, subcommandText)
    }
    
    /// Check if a string is likely an AutoCAD command name
    private func isLikelyCommand(_ text: String) -> Bool {
        // AutoCAD commands are typically:
        // - 3-15 characters
        // - All uppercase or title case
        // - Contain no spaces
        // - Made of alphabetic characters (and sometimes numbers)
        
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        guard !trimmed.isEmpty && trimmed.count >= 2 && trimmed.count <= 15 else {
            return false
        }
        
        // Check if mostly uppercase
        let uppercaseRatio = Double(trimmed.filter { $0.isUppercase }.count) / Double(trimmed.count)
        guard uppercaseRatio >= 0.7 else {
            return false
        }
        
        // Check if alphanumeric only
        return trimmed.allSatisfy { $0.isLetter || $0.isNumber }
    }
    
    /// Try to extract a command name from a prompt string
    /// Examples: "Specify first point: " → nil (no command)
    ///           "LINE - Specify first point: " → "LINE"
    private func extractCommandFromPrompt(_ text: String) -> String? {
        let components = text.split(separator: "-", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
        
        if components.count == 2, isLikelyCommand(components[0]) {
            return components[0]
        }
        
        return nil
    }
}

// MARK: - Error Types

enum AutoCADReaderError: LocalizedError {
    case autoCADNotRunning
    case accessibilityElementNotFound
    case commandLineWindowNotFound
    case cannotReadValue
    case custom(String)
    
    var errorDescription: String? {
        switch self {
        case .autoCADNotRunning:
            return "AutoCAD is not currently running"
        case .accessibilityElementNotFound:
            return "Could not access AutoCAD via Accessibility API"
        case .commandLineWindowNotFound:
            return "Could not find command line window in AutoCAD"
        case .cannotReadValue:
            return "Could not read value from Accessibility element"
        case .custom(let message):
            return message
        }
    }
}
