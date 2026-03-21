// SecurityValidator.swift
// TutorCast
//
// Centralized security validation for AutoCAD event data
// Implements Section 12 security requirements:
//   • Command name sanitization (max 64 chars)
//   • Subcommand sanitization (max 128 chars)
//   • Socket/TCP communication validation
//   • Plugin integrity verification
//   • One-way communication enforcement

import Foundation
import CryptoKit

// MARK: - Security Constants

struct SecurityConstants {
    // Command validation limits
    static let maxCommandNameLength = 64
    static let maxSubcommandLength = 128
    
    // Socket configuration
    static let unixSocketPath = "/tmp/tutorcast_autocad.sock"
    static let unixSocketPermissions: mode_t = 0o600  // User read/write only
    
    // TCP configuration
    static let tcpBindAddress = "127.0.0.1"
    static let tcpPort = 19848
    static let tcpTimeout: TimeInterval = 5.0
    
    // Parallels network ranges
    static let parallelsNetworks = ["10.211.55", "10.37.129"]
    
    // Shared folder settings
    static let sharedFolderPath = "~/tutorcast_events/"
    static let maxFileAge: TimeInterval = 30.0  // seconds
}

// MARK: - Command Validation

@MainActor
final class SecurityValidator {
    static let shared = SecurityValidator()
    
    private init() {}
    
    // MARK: - Command Data Validation
    
    /// Validate and sanitize AutoCAD command data
    /// - Parameters:
    ///   - commandName: The command name from plugin
    ///   - subcommand: Optional subcommand/prompt text
    /// - Returns: Validated command data, or nil if invalid
    func validateCommandData(commandName: String, subcommand: String? = nil) -> ValidatedCommandData? {
        // Validate command name
        guard !commandName.trimmingCharacters(in: .whitespaces).isEmpty else {
            print("[SecurityValidator] Rejected: empty command name")
            return nil
        }
        
        let sanitizedCommand = sanitizeCommandName(commandName)
        guard !sanitizedCommand.isEmpty else {
            print("[SecurityValidator] Rejected: command name failed sanitization")
            return nil
        }
        
        // Validate and sanitize subcommand if present
        var sanitizedSubcommand: String? = nil
        if let subcommand = subcommand {
            sanitizedSubcommand = sanitizeSubcommand(subcommand)
            if subcommand.isEmpty && !subcommand.trimmingCharacters(in: .whitespaces).isEmpty {
                print("[SecurityValidator] Warning: subcommand sanitization removed all content")
            }
        }
        
        return ValidatedCommandData(
            commandName: sanitizedCommand,
            subcommand: sanitizedSubcommand
        )
    }
    
    /// Sanitize command name (max 64 chars, remove control chars)
    private func sanitizeCommandName(_ input: String) -> String {
        var cleaned = input.trimmingCharacters(in: .whitespaces)
        
        // Remove control characters
        let controlCharacters = CharacterSet.controlCharacters.union(CharacterSet.illegalCharacters)
        cleaned = cleaned.filter { !controlCharacters.contains($0.unicodeScalars.first!) }
        
        // Remove newlines and carriage returns
        cleaned = cleaned.replacingOccurrences(of: "\n", with: "")
                         .replacingOccurrences(of: "\r", with: "")
                         .replacingOccurrences(of: "\0", with: "")
        
        // Enforce maximum length
        if cleaned.count > SecurityConstants.maxCommandNameLength {
            cleaned = String(cleaned.prefix(SecurityConstants.maxCommandNameLength))
        }
        
        return cleaned
    }
    
    /// Sanitize subcommand text (max 128 chars, remove control chars)
    private func sanitizeSubcommand(_ input: String) -> String {
        var cleaned = input.trimmingCharacters(in: .whitespaces)
        
        // Remove control characters
        let controlCharacters = CharacterSet.controlCharacters.union(CharacterSet.illegalCharacters)
        cleaned = cleaned.filter { !controlCharacters.contains($0.unicodeScalars.first!) }
        
        // Remove newlines and carriage returns
        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
                         .replacingOccurrences(of: "\r", with: " ")
                         .replacingOccurrences(of: "\0", with: "")
        
        // Collapse multiple spaces
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Enforce maximum length
        if cleaned.count > SecurityConstants.maxSubcommandLength {
            cleaned = String(cleaned.prefix(SecurityConstants.maxSubcommandLength))
        }
        
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
    
    // MARK: - Socket Security
    
    /// Verify Unix domain socket has correct permissions
    /// - Parameter socketPath: Path to the socket file
    /// - Returns: true if socket exists with correct permissions, false otherwise
    func verifySocketPermissions(socketPath: String = SecurityConstants.unixSocketPath) -> Bool {
        do {
            let fileManager = FileManager.default
            
            // Check if socket exists
            guard fileManager.fileExists(atPath: socketPath) else {
                print("[SecurityValidator] Socket does not exist at \(socketPath)")
                return false
            }
            
            // Get file attributes
            let attributes = try fileManager.attributesOfItem(atPath: socketPath)
            
            // Verify permissions (0o600 = user read/write, no group/other access)
            if let permissions = attributes[.posixPermissions] as? NSNumber {
                let mode = permissions.uint16Value
                let expectedMode: mode_t = 0o600
                
                if mode != expectedMode {
                    print("[SecurityValidator] Socket has incorrect permissions: \(String(mode, radix: 8)) (expected \(String(expectedMode, radix: 8)))")
                    return false
                }
            }
            
            return true
        } catch {
            print("[SecurityValidator] Error checking socket permissions: \(error)")
            return false
        }
    }
    
    /// Attempt to set socket permissions to 0o600
    /// - Parameter socketPath: Path to the socket file
    /// - Returns: true if permissions were set successfully
    func setSocketPermissions(socketPath: String = SecurityConstants.unixSocketPath) -> Bool {
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: socketPath
            )
            print("[SecurityValidator] Socket permissions set to 0o600 at \(socketPath)")
            return true
        } catch {
            print("[SecurityValidator] Failed to set socket permissions: \(error)")
            return false
        }
    }
    
    // MARK: - TCP Binding Validation
    
    /// Validate that TCP address is restricted to loopback or Parallels network
    /// - Parameter address: The IP address to bind to
    /// - Returns: true if address is allowed, false otherwise
    func validateTCPBindAddress(_ address: String) -> Bool {
        // Allow loopback
        if address == "127.0.0.1" || address == "localhost" {
            return true
        }
        
        // Allow Parallels networks
        for network in SecurityConstants.parallelsNetworks {
            if address.hasPrefix(network) {
                return true
            }
        }
        
        print("[SecurityValidator] TCP bind address not allowed: \(address)")
        return false
    }
    
    // MARK: - Plugin Integrity
    
    /// Compute SHA-256 checksum of plugin file
    /// - Parameter filePath: Path to the plugin file
    /// - Returns: Hexadecimal SHA-256 hash, or nil if file not readable
    func computePluginChecksum(filePath: String) -> String? {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02hhx", $0) }.joined()
        } catch {
            print("[SecurityValidator] Failed to compute checksum for \(filePath): \(error)")
            return nil
        }
    }
    
    /// Verify plugin file checksum against known-good value
    /// - Parameters:
    ///   - filePath: Path to the plugin file
    ///   - expectedChecksum: Known-good SHA-256 hash
    /// - Returns: true if checksum matches, false otherwise
    func verifyPluginIntegrity(filePath: String, expectedChecksum: String) -> Bool {
        guard let actualChecksum = computePluginChecksum(filePath: filePath) else {
            return false
        }
        
        let matches = actualChecksum.lowercased() == expectedChecksum.lowercased()
        
        if !matches {
            print("[SecurityValidator] Plugin checksum mismatch!")
            print("[SecurityValidator] Expected: \(expectedChecksum)")
            print("[SecurityValidator] Actual:   \(actualChecksum)")
        } else {
            print("[SecurityValidator] Plugin checksum verified: \(actualChecksum)")
        }
        
        return matches
    }
    
    // MARK: - Communication Validation
    
    /// Validate that no write operations would be performed on socket/TCP
    /// This enforces one-way communication (AutoCAD → TutorCast only)
    /// - Parameter operation: The operation type to validate
    /// - Returns: true if operation is allowed (read-only), false if write operation
    func validateReadOnlyCommunication(operation: CommunicationOperation) -> Bool {
        switch operation {
        case .read, .receiveData:
            return true  // Read operations are allowed
        case .write, .sendData:
            print("[SecurityValidator] REJECTED: Attempted write operation on plugin channel")
            print("[SecurityValidator] TutorCast must never send commands back to AutoCAD")
            return false
        }
    }
    
    // MARK: - Shared Folder Cleanup
    
    /// Check if file is stale (older than max age)
    /// - Parameters:
    ///   - filePath: Path to the file
    ///   - maxAge: Maximum age in seconds (default 30)
    /// - Returns: true if file is older than maxAge, false otherwise
    func isFileStale(filePath: String, maxAge: TimeInterval = SecurityConstants.maxFileAge) -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
            
            guard let modificationDate = attributes[.modificationDate] as? Date else {
                print("[SecurityValidator] Could not determine modification date for \(filePath)")
                return true  // Treat as stale if we can't determine age
            }
            
            let age = Date().timeIntervalSince(modificationDate)
            return age > maxAge
        } catch {
            print("[SecurityValidator] Error checking file age for \(filePath): \(error)")
            return true  // Treat as stale on error
        }
    }
    
    /// Clean up stale files in shared folder
    /// - Parameters:
    ///   - folderPath: Path to shared folder
    ///   - maxAge: Maximum age in seconds (default 30)
    /// - Returns: Number of files deleted
    func cleanupStaleFiles(folderPath: String = SecurityConstants.sharedFolderPath, maxAge: TimeInterval = SecurityConstants.maxFileAge) -> Int {
        let fileManager = FileManager.default
        let expandedPath = (folderPath as NSString).expandingTildeInPath
        
        do {
            let files = try fileManager.contentsOfDirectory(atPath: expandedPath)
            var deletedCount = 0
            
            for file in files {
                let filePath = (expandedPath as NSString).appendingPathComponent(file)
                
                if isFileStale(filePath: filePath, maxAge: maxAge) {
                    do {
                        try fileManager.removeItem(atPath: filePath)
                        print("[SecurityValidator] Deleted stale file: \(file)")
                        deletedCount += 1
                    } catch {
                        print("[SecurityValidator] Failed to delete \(file): \(error)")
                    }
                }
            }
            
            return deletedCount
        } catch {
            print("[SecurityValidator] Error accessing shared folder: \(error)")
            return 0
        }
    }
}

// MARK: - Supporting Types

/// Result of command data validation
struct ValidatedCommandData {
    let commandName: String
    let subcommand: String?
}

/// Communication operation types for validation
enum CommunicationOperation {
    case read
    case receiveData
    case write
    case sendData
}

// MARK: - Extension for Plugin Checksum Storage

/// Extension to access plugin checksums from app bundle
extension SecurityValidator {
    
    /// Get known-good checksum for Windows plugin from app bundle
    /// - Returns: SHA-256 hash, or nil if not found
    func getWindowsPluginChecksum() -> String? {
        // In production, this would load from a plist or configuration embedded in the app
        // For now, return nil to indicate not configured
        // TODO: Embed checksums in Info.plist or separate configuration file
        return nil
    }
    
    /// Get known-good checksum for macOS Python plugin
    /// - Returns: SHA-256 hash, or nil if not found
    func getMacOSPluginChecksum() -> String? {
        // In production, this would load from a plist or configuration
        return nil
    }
}
