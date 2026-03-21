// ParallelsWindowsAutoCADReader.swift
// TutorCast
//
// Reads the active command and subcommand from AutoCAD running inside
// Parallels Desktop (Windows VM on top of macOS).
//
// Strategy:
//   1. Use Parallels' macOS API to interact with the guest OS
//   2. Launch a helper tool inside the Windows VM that monitors AutoCAD's UIA (UI Automation)
//   3. Communicate via IPC (sockets) or clipboard shared memory
//   4. Extract command name and prompt from AutoCAD's command bar
//
// Implementation approach:
//   • Use PrlSDK (Parallels Desktop SDK) or simpler method: Direct socket communication
//   • Helper process in Windows reads AutoCAD via Windows UI Automation (UIA)
//   • Share command state over TCP socket (localhost only for security)
//   • macOS reads from socket at regular intervals
//
// Fallback if helper not available:
//   • Detect if AutoCAD window is in Parallels
//   • Fall back to keyboard-only mode (not ideal, but functional)
//
// Note on security:
//   • Communication is local-only (127.0.0.1:port)
//   • No credentials transmitted
//   • Restrict to user processes only

import Foundation
import AppKit

@MainActor
final class ParallelsWindowsAutoCADReader: NSObject, AutoCADReader {
    
    // MARK: - Configuration
    
    /// Default port for Windows helper to listen on
    private static let defaultHelperPort: UInt16 = 24680
    
    /// Timeout for socket operations
    private static let socketTimeout: TimeInterval = 2.0
    
    // MARK: - Private State
    
    private var helperPort: UInt16 = defaultHelperPort
    private var lastSuccessfulRead: Date?
    private var failureCount: Int = 0
    private let maxConsecutiveFailures: Int = 10  // After 10 failures, give up
    
    override init() {
        super.init()
    }
    
    // MARK: - AutoCADReader Protocol
    
    func isAutoCADRunning() async -> Bool {
        // Check if Parallels Desktop is running
        guard isParallelsRunning() else {
            print("[ParallelsAutoCADReader] Parallels Desktop not found")
            return false
        }
        
        // Check if Windows VM is running
        guard await isWindowsVMRunning() else {
            print("[ParallelsAutoCADReader] No running Windows VM detected")
            return false
        }
        
        // Check if helper process is listening on the expected port
        let isHelperAvailable = await checkHelperProcess()
        
        if isHelperAvailable {
            print("[ParallelsAutoCADReader] ✅ Helper process is available")
            failureCount = 0
            return true
        } else {
            print("[ParallelsAutoCADReader] ⚠️  Helper process not responding")
            print("[ParallelsAutoCADReader] Make sure TutorCastHelper.exe is running in Windows")
            return false
        }
    }
    
    func readCommandState() async throws -> AutoCADCommandState {
        // Prevent repeated failures from blocking the system
        if failureCount >= maxConsecutiveFailures {
            throw AutoCADReaderError.custom("Helper process failed too many times; giving up")
        }
        
        do {
            let state = try await requestCommandStateFromHelper()
            lastSuccessfulRead = Date()
            failureCount = 0
            return state
        } catch {
            failureCount += 1
            throw error
        }
    }
    
    // MARK: - Parallels Detection
    
    /// Check if Parallels Desktop is installed and running
    private func isParallelsRunning() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        let parallelsApp = runningApps.first { app in
            let bundleID = app.bundleIdentifier ?? ""
            let name = app.localizedName ?? ""
            return bundleID.lowercased().contains("parallels") ||
                   name.lowercased().contains("parallels")
        }
        
        return parallelsApp != nil
    }
    
    /// Check if a Windows VM is running in Parallels
    private func isWindowsVMRunning() async -> Bool {
        // Try to detect via prlctl command (Parallels command-line tool)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/prlctl")
        process.arguments = ["list", "--all", "-o", "status"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Check if any VM is in "running" state
            return output.lowercased().contains("running")
        } catch {
            print("[ParallelsAutoCADReader] Could not check VM status: \(error)")
            return false
        }
    }
    
    /// Check if the Windows helper process is responding
    private func checkHelperProcess() async -> Bool {
        do {
            let state = try await requestCommandStateFromHelper()
            // If we got here, helper is alive
            return !state.commandName.isEmpty || !state.subcommandText.isEmpty || true
        } catch {
            return false
        }
    }
    
    // MARK: - Socket Communication
    
    /// Request command state from the Windows helper process
    private func requestCommandStateFromHelper() async throws -> AutoCADCommandState {
        return try await withCheckedThrowingContinuation { continuation in
            let host = "127.0.0.1"
            let port = helperPort
            
            // Create a socket connection
            var socketfd: Int32 = -1
            var addr = sockaddr_in()
            
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(port).bigEndian
            addr.sin_addr.s_addr = inet_addr(host)
            addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
            
            socketfd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            
            guard socketfd >= 0 else {
                continuation.resume(throwing: AutoCADReaderError.custom("Could not create socket"))
                return
            }
            
            defer { close(socketfd) }
            
            // Set timeout
            var timeout = timeval()
            timeout.tv_sec = Int(Self.socketTimeout)
            timeout.tv_usec = 0
            setsockopt(socketfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(socketfd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            
            // Connect
            let result = withUnsafePointer(to: &addr) {
                connect(socketfd, UnsafeRawPointer($0).assumingMemoryBound(to: sockaddr.self), socklen_t(MemoryLayout<sockaddr_in>.size))
            }
            
            guard result >= 0 else {
                continuation.resume(throwing: AutoCADReaderError.custom("Connection refused: helper not responding"))
                return
            }
            
            // Send request: simple JSON or newline-terminated command
            let request = "GET_COMMAND_STATE\n"
            guard let requestData = request.data(using: .utf8) else {
                continuation.resume(throwing: AutoCADReaderError.custom("Could not encode request"))
                return
            }
            
            let sentBytes = send(socketfd, (requestData as NSData).bytes, requestData.count, 0)
            guard sentBytes > 0 else {
                continuation.resume(throwing: AutoCADReaderError.custom("Send failed"))
                return
            }
            
            // Receive response: JSON with command state
            var buffer = [UInt8](repeating: 0, count: 4096)
            let receivedBytes = recv(socketfd, &buffer, buffer.count - 1, 0)
            
            guard receivedBytes > 0 else {
                continuation.resume(throwing: AutoCADReaderError.custom("No response from helper"))
                return
            }
            
            let responseData = Data(bytes: buffer, count: receivedBytes)
            guard let responseString = String(data: responseData, encoding: .utf8) else {
                continuation.resume(throwing: AutoCADReaderError.custom("Invalid response encoding"))
                return
            }
            
            // Parse response
            do {
                let state = try parseHelperResponse(responseString)
                continuation.resume(returning: state)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Parse the response from the Windows helper
    /// Format: "COMMAND_NAME\nSUBCOMMAND_TEXT\n" or JSON
    private func parseHelperResponse(_ response: String) throws -> AutoCADCommandState {
        let lines = response
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        
        // Try JSON format first
        if let jsonData = response.data(using: .utf8) {
            do {
                if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: String] {
                    let commandName = json["command"] ?? ""
                    let subcommandText = json["subcommand"] ?? ""
                    return AutoCADCommandState(
                        commandName: commandName,
                        subcommandText: subcommandText
                    )
                }
            } catch {
                // Fall through to line-based parsing
            }
        }
        
        // Line-based format: first line = command, second line = subcommand
        if lines.count >= 1 {
            let commandName = lines[0]
            let subcommandText = lines.count >= 2 ? lines[1] : ""
            
            return AutoCADCommandState(
                commandName: commandName,
                subcommandText: subcommandText
            )
        }
        
        throw AutoCADReaderError.custom("Could not parse helper response")
    }
    
    // MARK: - Helper Installation & Launch
    
    /// Ensure the Windows helper is available and running
    /// This would be called during setup or if helper is not detected
    func ensureHelperRunning() async -> Bool {
        // Check if already running
        if await checkHelperProcess() {
            return true
        }
        
        // Try to launch the helper
        let helperPath = "/Applications/TutorCast.app/Contents/Resources/TutorCastHelper.exe"
        
        // In a real implementation, we would:
        // 1. Copy TutorCastHelper.exe to a shared folder
        // 2. Use Parallels SDK or prlctl to execute it in the guest
        // 3. Wait for it to respond
        
        print("[ParallelsAutoCADReader] Helper launch not yet implemented")
        return false
    }
}

// MARK: - Darwin Socket Functions (imported from Darwin)
import Darwin

// Extension to add socket headers if needed
fileprivate func inet_addr(_ str: String) -> in_addr_t {
    var result = in_addr()
    inet_pton(AF_INET, str, &result.s_addr)
    return result.s_addr
}
