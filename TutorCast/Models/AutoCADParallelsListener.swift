// AutoCADParallelsListener.swift (Clean Socket Implementation)
// Listens on TCP port 19848 for events from the Windows AutoCAD plugin
// using raw sockets to avoid NetworkFramework IPv6 sandbox restrictions

import Foundation
import Darwin
import AppKit

final class AutoCADParallelsListener {
    static let shared = AutoCADParallelsListener()
    
    private let port: UInt16 = 19848
    private var serverSocket: Int32 = -1
    private var isListening = false
    private var listenerThread: Thread?
    
    /// Callback for received events
    var onEvent: ((AutoCADCommandEvent) -> Void)?
    
    func start() {
        print("[AutoCADParallelsListener] ▶ start() called")
        startTCPServer()
    }
    
    func stop() {
        print("[AutoCADParallelsListener] ⏹ stop() called")
        isListening = false
        if serverSocket != -1 {
            close(serverSocket)
            serverSocket = -1
        }
    }
    
    private func startTCPServer() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            print("[AutoCADParallelsListener] ▶ startTCPServer() executing on background thread")
            
            // Create socket
            let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard socket != -1 else {
                print("[AutoCADParallelsListener] ❌ Failed to create socket")
                return
            }
            print("[AutoCADParallelsListener] ✓ Socket created: FD=\(socket)")
            
            // Configure socket options
            var yes: Int32 = 1
            setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
            print("[AutoCADParallelsListener] ✓ Socket options set")
            
            // Bind to port
            var serverAddr = sockaddr_in()
            serverAddr.sin_family = sa_family_t(AF_INET)
            serverAddr.sin_port = CFSwapInt16HostToBig(self.port)
            serverAddr.sin_addr.s_addr = inet_addr("0.0.0.0")  // All interfaces
            
            let bindResult = withUnsafePointer(to: &serverAddr) { ptr in
                bind(socket, UnsafeRawPointer(ptr).assumingMemoryBound(to: sockaddr.self), socklen_t(MemoryLayout<sockaddr_in>.size))
            }
            
            guard bindResult != -1 else {
                print("[AutoCADParallelsListener] ❌ Failed to bind socket on port \(self.port): errno=\(errno)")
                close(socket)
                return
            }
            print("[AutoCADParallelsListener] ✓ Socket bound to port \(self.port)")
            
            // Listen for connections
            guard listen(socket, 5) != -1 else {
                print("[AutoCADParallelsListener] ❌ Failed to listen: errno=\(errno)")
                close(socket)
                return
            }
            print("[AutoCADParallelsListener] ✓ Socket listening")
            
            self.serverSocket = socket
            self.isListening = true
            
            DispatchQueue.main.async {
                print("[AutoCADParallelsListener] ✅ TCP server listening on 0.0.0.0:\(self.port)")
            }
            
            // Accept connections
            while self.isListening {
                var clientAddr = sockaddr_in()
                var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                
                let clientSocket = accept(socket, UnsafeMutableRawPointer(&clientAddr).assumingMemoryBound(to: sockaddr.self), &clientAddrLen)
                
                guard clientSocket != -1 else {
                    if errno == EINTR {
                        continue
                    }
                    if self.isListening {
                        print("[AutoCADParallelsListener] Accept failed: errno=\(errno)")
                    }
                    break
                }
                
                Task { @MainActor in
                    print("[AutoCADParallelsListener] 🔗 New connection from Windows plugin")
                }
                
                // Handle client in background
                DispatchQueue.global().async {
                    self.handleClientConnection(clientSocket)
                }
            }
            
            close(socket)
        }
    }
    
    private func handleClientConnection(_ clientSocket: Int32) {
        defer { close(clientSocket) }
        
        var buffer = [CChar](repeating: 0, count: 8192)
        var accumulator = ""
        
        while isListening {
            let bytesRead = read(clientSocket, &buffer, buffer.count - 1)
            
            if bytesRead <= 0 {
                break
            }
            
            buffer[bytesRead] = 0
            if let chunk = String(cString: &buffer, encoding: .utf8) {
                accumulator.append(chunk)
                
                // Process complete lines (newline-delimited JSON)
                let lines = accumulator.split(separator: "\n", omittingEmptySubsequences: false)
                
                for i in 0..<(lines.count - 1) {
                    let line = String(lines[i])
                    processEventLine(line)
                }
                
                // Keep incomplete line for next read
                accumulator = String(lines.last ?? "")
            }
        }
    }
    
    private func processEventLine(_ line: String) {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        do {
            if let jsonData = line.data(using: .utf8) {
                let event = try JSONDecoder().decode(AutoCADCommandEvent.self, from: jsonData)
                DispatchQueue.main.async {
                    print("[AutoCADParallelsListener] 📨 Event received: \(event.commandName)")
                    self.onEvent?(event)
                }
            }
        } catch {
            print("[AutoCADParallelsListener] ⚠️ Failed to parse event: \(error)")
        }
    }
}
