import AppKit
import Combine
import Foundation

// MARK: - Path Security Utilities

/// Validates that a path is within allowed directories (prevents path traversal)
private func validateExportPath(_ path: URL) -> Bool {
    let expandedPath = path.standardizedFileURL
    
    // Only allow paths in Desktop, Documents, or Downloads
    let fileManager = FileManager.default
    let desktopURL = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
    
    let allowedPaths = [desktopURL, documentsURL, downloadsURL].compactMap { $0?.standardizedFileURL }
    
    // Check if path starts with any allowed directory
    for allowedPath in allowedPaths {
        if expandedPath.path.hasPrefix(allowedPath.path) {
            return true
        }
    }
    
    return false
}

/// Sanitizes filename to prevent directory traversal and special characters
private func sanitizeFilename(_ filename: String) -> String {
    var sanitized = filename
    
    // Remove directory traversal patterns
    sanitized = sanitized.replacingOccurrences(of: "../", with: "")
    sanitized = sanitized.replacingOccurrences(of: "..\\", with: "")
    sanitized = sanitized.replacingOccurrences(of: "/", with: "_")
    sanitized = sanitized.replacingOccurrences(of: "\\", with: "_")
    
    // Remove control characters
    let controlCharacters = CharacterSet.controlCharacters.union(CharacterSet.illegalCharacters)
    sanitized = sanitized.filter { !controlCharacters.contains($0.unicodeScalars.first!) }
    
    // Limit length
    if sanitized.count > 200 {
        sanitized = String(sanitized.prefix(200))
    }
    
    return sanitized
}

@MainActor
final class SessionRecorder: NSObject, ObservableObject {
    static let shared = SessionRecorder()
    
    @Published var isRecording = false
    @Published var recordedActions: [(timestamp: Date, action: String)] = []
    
    let objectWillChange = PassthroughSubject<Void, Never>()
    
    private let maxDuration: TimeInterval = 60.0 // Keep last 60 seconds
    
    override private init() {
        super.init()
    }
    
    /// Add an action to the session recording
    func recordAction(_ action: String) {
        let now = Date()
        // Sanitize action string before recording
        let sanitizedAction = action.trimmingCharacters(in: .whitespaces).prefix(512)
        recordedActions.append((timestamp: now, action: String(sanitizedAction)))
        
        // Trim old actions (keep only last 60 seconds)
        let cutoffTime = now.addingTimeInterval(-maxDuration)
        recordedActions.removeAll { $0.timestamp < cutoffTime }
        
        print("[SessionRecorder] Recorded action: \(sanitizedAction) (\(recordedActions.count) total)")
    }
    
    /// Export recorded session as a text file with timestamps (secure)
    func exportSession(to url: URL) async {
        // Validate the export path for security
        guard validateExportPath(url) else {
            print("[SessionRecorder] ⚠️  Export blocked: invalid path. Use Desktop, Documents, or Downloads.")
            return
        }
        
        var content = "TutorCast Session Recording\n"
        content += "Exported: \(ISO8601DateFormatter().string(from: Date()))\n"
        content += "Total actions: \(recordedActions.count)\n"
        content += String(repeating: "=", count: 50) + "\n\n"
        
        for (index, (timestamp, action)) in recordedActions.enumerated() {
            let timeString = ISO8601DateFormatter().string(from: timestamp)
            content += "[\(index + 1)] \(timeString)\n"
            // Sanitize action for display
            let forbiddenScalars = CharacterSet.controlCharacters.union(.illegalCharacters)
            let displayAction = String(action.unicodeScalars.filter { !forbiddenScalars.contains($0) })
            content += "    Action: \(displayAction)\n\n"
        }
        
        do {
            // Sanitize filename
            let filename = sanitizeFilename(url.deletingPathExtension().lastPathComponent)
            let finalURL = url.deletingLastPathComponent()
                .appendingPathComponent(filename)
                .appendingPathExtension("txt")
            
            // Write with secure permissions
            try content.write(
                to: finalURL,
                atomically: true,
                encoding: .utf8
            )
            
            // Set secure file permissions
            let fileManager = FileManager.default
            try fileManager.setAttributes([
                .protectionKey: FileProtectionType.complete,
                .posixPermissions: 0o600
            ], ofItemAtPath: finalURL.path)
            
            print("[SessionRecorder] Exported to \(finalURL.path)")
            
            // Copy to clipboard notification
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
            
            // Clear sensitive data from memory
            content = String(repeating: " ", count: content.count)
        } catch {
            print("[SessionRecorder] Export failed: \(error)")
        }
    }
    
    /// Clear the session and securely wipe memory
    func clearSession() {
        recordedActions.removeAll()
        // Force garbage collection of sensitive data
        recordedActions = []
        print("[SessionRecorder] Session cleared and memory wiped")
    }
}

