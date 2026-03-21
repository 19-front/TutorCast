// AutoCADNativeListener.swift
// Listens on a Unix domain socket for events from the macOS AutoCAD native plugin.
// Falls back to FSEvents file watching for the LISP fallback plugin.
//
// Transport: Newline-delimited JSON on Unix socket or FSEvents file updates.

import Foundation
import Darwin

@MainActor
final class AutoCADNativeListener: ObservableObject {
    static let shared = AutoCADNativeListener()
    
    /// Unix domain socket path for Python plugin communication
    private let socketPath = "/tmp/tutorcast_autocad.sock"
    
    /// Fallback file path for LISP plugin (FSEvents monitoring)
    private let fallbackFilePath = "/tmp/tutorcast_event.json"
    
    /// Callback when an event is received
    var onEvent: ((AutoCADCommandEvent) -> Void)?
    
    /// Socket file descriptor (-1 if not connected)
    private var serverSocket: Int32 = -1
    
    /// Client socket file descriptor (if connected)
    private var clientSocket: Int32 = -1
    
    /// Thread for accepting connections
    private var acceptThread: Thread?
    
    /// FSEvents stream for LISP fallback monitoring
    private var fsEventStream: FSEventStreamRef?
    
    /// Last file modification time (to debounce FSEvents)
    private var lastFileUpdateTime: TimeInterval = 0
    
    // MARK: - Lifecycle
    
    func start() {
        startUnixSocketServer()
        startFSEventsFallback()
    }
    
    func stop() {
        stopUnixSocketServer()
        stopFSEventsFallback()
    }
    
    // MARK: - Unix Domain Socket Server
    
    private func startUnixSocketServer() {
        // Clean up any stale socket file
        try? FileManager.default.removeItem(atPath: socketPath)
        
        acceptThread = Thread { [weak self] in
            self?.runSocketServer()
        }
        acceptThread?.name = "com.tutorcast.native-listener"
        acceptThread?.start()
    }
    
    private func runSocketServer() {
        // Create Unix domain socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("[AutoCADNativeListener] Failed to create socket: \(errno)")
            return
        }
        
        // Prepare socket address
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        // Ensure path fits in sun_path buffer (max 104 bytes on macOS)
        guard socketPath.utf8.count < Int(MemoryLayout.size(ofValue: addr.sun_path)) else {
            print("[AutoCADNativeListener] Socket path too long: \(socketPath)")
            close(serverSocket)
            return
        }
        
        // Copy path to sockaddr
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            let path = socketPath.utf8
            for (index, byte) in path.enumerated() {
                buffer[index] = byte
            }
        }
        
        // Bind socket
        let addrSize = MemoryLayout<sockaddr_un>.size
        let result = withUnsafeBytes(of: &addr) { buffer in
            bind(serverSocket, buffer.baseAddress?.assumingMemoryBound(to: sockaddr.self), socklen_t(addrSize))
        }
        
        guard result == 0 else {
            print("[AutoCADNativeListener] Failed to bind socket: \(errno)")
            close(serverSocket)
            return
        }
        
        // Set permissions (readable/writable by user)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: socketPath)
        chmod(socketPath, 0o600)
        
        // Listen for connections
        guard listen(serverSocket, 1) == 0 else {
            print("[AutoCADNativeListener] Failed to listen on socket: \(errno)")
            close(serverSocket)
            return
        }
        
        print("[AutoCADNativeListener] Listening on \(socketPath)")
        
        // Accept connections loop
        while serverSocket >= 0 {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            
            let newSocket = accept(serverSocket, withUnsafeMutableBytes(of: &clientAddr) { buffer in
                buffer.baseAddress?.assumingMemoryBound(to: sockaddr.self)
            }, &clientAddrLen)
            
            guard newSocket >= 0 else {
                if errno == EINTR { continue }  // Interrupted, retry
                if errno != EBADF { print("[AutoCADNativeListener] Accept error: \(errno)") }
                break
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.handleSocketConnection(newSocket)
            }
        }
        
        print("[AutoCADNativeListener] Socket server stopped")
        close(serverSocket)
        serverSocket = -1
    }
    
    private func handleSocketConnection(_ socket: Int32) {
        clientSocket = socket
        print("[AutoCADNativeListener] Client connected")
        
        // Set non-blocking with timeout
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        // Read newline-delimited JSON messages
        let bufferSize = 8192
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var accumulator = ""
        
        while serverSocket >= 0 {
            let bytesRead = recv(socket, &buffer, bufferSize, 0)
            
            if bytesRead <= 0 {
                if bytesRead < 0 && errno != EAGAIN && errno != EWOULDBLOCK {
                    print("[AutoCADNativeListener] Socket read error: \(errno)")
                }
                break
            }
            
            if let chunk = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
                accumulator.append(chunk)
                
                // Process complete lines (newline-delimited)
                while let newlineIdx = accumulator.firstIndex(of: "\n") {
                    let line = String(accumulator[..<newlineIdx]).trimmingCharacters(in: .whitespaces)
                    accumulator.removeFirst(accumulator.distance(from: accumulator.startIndex, to: newlineIdx) + 1)
                    
                    if !line.isEmpty {
                        parseAndEmitEvent(line)
                    }
                }
            }
        }
        
        close(socket)
        clientSocket = -1
        print("[AutoCADNativeListener] Client disconnected")
    }
    
    private func stopUnixSocketServer() {
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        if clientSocket >= 0 {
            close(clientSocket)
            clientSocket = -1
        }
        try? FileManager.default.removeItem(atPath: socketPath)
    }
    
    // MARK: - FSEvents Fallback (for LISP plugin)
    
    private func startFSEventsFallback() {
        var context = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = Unmanaged.passUnretained(self).toOpaque()
        
        let callback: FSEventStreamCallback = { (stream, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let callbackInfo = clientCallBackInfo else { return }
            let listener = Unmanaged<AutoCADNativeListener>.fromOpaque(callbackInfo).takeUnretainedValue()
            listener.onFSEventsUpdate()
        }
        
        let pathsArray = ["/tmp" as CFString] as CFArray
        
        fsEventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,  // Latency: 100ms
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        )
        
        if let stream = fsEventStream {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            FSEventStreamStart(stream)
            print("[AutoCADNativeListener] FSEvents monitoring started for LISP fallback")
        }
    }
    
    private func onFSEventsUpdate() {
        // Debounce: only read if file was modified after last read
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fallbackFilePath),
              let modDate = attrs[.modificationDate] as? Date else {
            return
        }
        
        let currentTime = modDate.timeIntervalSince1970
        guard currentTime > lastFileUpdateTime + 0.05 else { return }  // Skip if too soon
        
        lastFileUpdateTime = currentTime
        readFallbackFile()
    }
    
    private func readFallbackFile() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: fallbackFilePath)),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }
        
        parseAndEmitEvent(jsonString)
    }
    
    private func stopFSEventsFallback() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            fsEventStream = nil
        }
    }
    
    // MARK: - Event Parsing
    
    private func parseAndEmitEvent(_ jsonString: String) {
        guard let event = AutoCADCommandEvent.fromJSONString(jsonString) else {
            print("[AutoCADNativeListener] Failed to parse event: \(jsonString)")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
}
