// AutoCADParallelsListener.swift
// Listens on TCP port 19848 for events from the Windows AutoCAD plugin
// running inside Parallels Desktop.
//
// The Windows plugin connects from the VM to the macOS host at 10.211.55.2:19848
// (or 10.37.129.2 as fallback).
//
// Transport: Newline-delimited JSON over TCP socket, UTF-8 encoded.

import Foundation
import Network

@MainActor
final class AutoCADParallelsListener: ObservableObject {
    static let shared = AutoCADParallelsListener()
    
    /// TCP port for Windows plugin connections
    private let port: UInt16 = 19848
    
    /// Network listener (TCP server)
    private var listener: NWListener?
    
    /// Active client connections
    private var connections: [NWConnection] = []
    
    /// DispatchSourceFileSystemObject for shared folder monitoring
    private var sharedFolderWatcher: DispatchSourceFileSystemObject?
    
    /// Path to shared folder fallback
    private let sharedFolderPath: URL
    
    /// Callback when an event is received from either channel
    var onEvent: ((AutoCADCommandEvent) -> Void)?
    
    init() {
        self.sharedFolderPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("tutorcast_events")
    }
    
    // MARK: - Lifecycle
    
    func start() {
        startTCPServer()
        startSharedFolderFallback()
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        connections.removeAll()
        sharedFolderWatcher?.cancel()
        sharedFolderWatcher = nil
    }
    
    // MARK: - TCP Server
    
    private func startTCPServer() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        
        // Disable encryption (local network only)
        params.defaultProtocolStack.mediaAccess = .disable
        
        do {
            guard let port = NWEndpoint.Port(rawValue: self.port) else {
                print("[AutoCADParallelsListener] Invalid port: \(self.port)")
                return
            }
            
            listener = try NWListener(using: params, on: port)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("[AutoCADParallelsListener] TCP server listening on port \(self?.port ?? 0)")
                case .failed(let error):
                    print("[AutoCADParallelsListener] TCP server failed: \(error)")
                case .cancelled:
                    print("[AutoCADParallelsListener] TCP server cancelled")
                default:
                    break
                }
            }
            
            listener?.start(queue: .main)
        } catch {
            print("[AutoCADParallelsListener] Failed to start TCP server: \(error)")
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        print("[AutoCADParallelsListener] New connection from Windows plugin")
        connections.append(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[AutoCADParallelsListener] Connection established")
                self?.receiveData(from: connection, buffer: "")
            case .failed(let error):
                print("[AutoCADParallelsListener] Connection failed: \(error)")
                self?.connections.removeAll { $0 === connection }
            case .cancelled:
                self?.connections.removeAll { $0 === connection }
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func receiveData(from connection: NWConnection, buffer: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, !data.isEmpty {
                if let chunk = String(data: data, encoding: .utf8) {
                    var accumulated = buffer + chunk
                    
                    // Parse newline-delimited JSON
                    while let newlineRange = accumulated.range(of: "\n") {
                        let line = String(accumulated[accumulated.startIndex..<newlineRange.lowerBound])
                        accumulated.removeFirst(accumulated.distance(from: accumulated.startIndex, to: newlineRange.upperBound))
                        
                        if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                            self.parseAndDispatch(line)
                        }
                    }
                    
                    // Continue receiving if not complete
                    if !isComplete {
                        self.receiveData(from: connection, buffer: accumulated)
                    }
                }
            }
            
            if isComplete || error != nil {
                self.connections.removeAll { $0 === connection }
                print("[AutoCADParallelsListener] Connection closed")
            }
        }
    }
    
    // MARK: - Event Parsing
    
    private func parseAndDispatch(_ jsonString: String) {
        guard let event = AutoCADCommandEvent.fromJSONString(jsonString) else {
            print("[AutoCADParallelsListener] Failed to parse event: \(jsonString)")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
    
    // MARK: - Shared Folder Fallback
    
    private func startSharedFolderFallback() {
        // Create shared folder if it doesn't exist
        try? FileManager.default.createDirectory(
            at: sharedFolderPath,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Open directory for monitoring
        let fd = open(sharedFolderPath.path, O_EVTONLY)
        guard fd >= 0 else {
            print("[AutoCADParallelsListener] Failed to open shared folder for monitoring: \(sharedFolderPath)")
            return
        }
        
        // Create dispatch source to monitor file writes
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.main
        )
        
        source.setEventHandler { [weak self] in
            self?.processSharedFolderEvents()
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        source.resume()
        sharedFolderWatcher = source
        
        print("[AutoCADParallelsListener] Monitoring shared folder fallback: \(sharedFolderPath)")
    }
    
    private func processSharedFolderEvents() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sharedFolderPath,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter({ $0.pathExtension == "json" }) else {
            return
        }
        
        // Process files in alphabetical order (oldest first by filename timestamp)
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: file),
                  let jsonString = String(data: data, encoding: .utf8) else {
                // Delete corrupted file
                try? FileManager.default.removeItem(at: file)
                continue
            }
            
            // Parse and emit event
            parseAndDispatch(jsonString)
            
            // Delete processed file
            try? FileManager.default.removeItem(at: file)
        }
    }
}
