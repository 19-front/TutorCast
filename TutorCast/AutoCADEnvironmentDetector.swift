// AutoCADEnvironmentDetector.swift
// TutorCast
//
// Automatic detection of AutoCAD environment:
//   • Native macOS (Accessibility API)
//   • Parallels Windows VM (network scan + socket)
//   • Manual override via UserDefaults
//
// Re-detection runs:
//   • On app launch (3s delay for initialization)
//   • Every 30 seconds in background
//   • On workspace notifications (app launch/quit)
//
// Publishes environment state for menu bar UI feedback

import AppKit
import Foundation
import Combine

// MARK: - Environment Enum

enum AutoCADEnvironment: Equatable {
    case notRunning
    case nativeMac(version: String?)           // AutoCAD for macOS with optional version
    case parallelsWindows(vmIP: String)        // IP of Windows VM running AutoCAD
    case unknown
    
    var displayName: String {
        switch self {
        case .notRunning:
            return "Not Running"
        case .nativeMac(let version):
            return "macOS" + (version.map { " (\($0))" } ?? "")
        case .parallelsWindows(let ip):
            return "Parallels (\(ip))"
        case .unknown:
            return "Unknown"
        }
    }
}

// MARK: - Main Detector Class

@MainActor
final class AutoCADEnvironmentDetector: ObservableObject {
    static let shared = AutoCADEnvironmentDetector()
    
    // MARK: - Published Properties
    
    @Published var current: AutoCADEnvironment = .unknown
    @Published var isDetecting: Bool = false
    
    // MARK: - Constants
    
    private let detectionInterval: TimeInterval = 30.0      // Re-detect every 30 seconds
    private let launchDelay: TimeInterval = 3.0             // Delay before first detection
    private let tcpTimeout: TimeInterval = 0.2              // 200ms TCP connect timeout
    
    // Parallels network ranges (default)
    private let parallelsNetworks = [
        "10.211.55",      // Host-only adapter (primary)
        "10.37.129"       // Shared adapter (alternative)
    ]
    private let autocadWindowsPort = 19848  // TutorCast Windows plugin port
    
    // UserDefaults keys
    private let overrideKey = "autocad.environment.override"
    private let lastDetectionKey = "autocad.environment.lastDetection"
    
    // MARK: - Private State
    
    private var detectionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var workspaceObserver: NSObjectProtocol?
    
    private init() {
        setupWorkspaceNotifications()
    }
    
    // MARK: - Lifecycle
    
    func startDetection() {
        print("[AutoCADEnvironmentDetector] Starting detection...")
        
        // First detection: delayed to allow apps to initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + launchDelay) { [weak self] in
            Task {
                await self?.performDetection()
            }
        }
        
        // Periodic re-detection
        detectionTimer = Timer.scheduledTimer(withTimeInterval: detectionInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.performDetection()
            }
        }
    }
    
    func stopDetection() {
        print("[AutoCADEnvironmentDetector] Stopping detection...")
        detectionTimer?.invalidate()
        detectionTimer = nil
    }
    
    /// Force immediate re-detection
    func forceDetection() async {
        await performDetection()
    }
    
    // MARK: - Detection Pipeline
    
    private func performDetection() async {
        // Check manual override first
        if let override = checkManualOverride() {
            self.current = override
            return
        }
        
        isDetecting = true
        defer { isDetecting = false }
        
        // Step 1: Check for native macOS AutoCAD
        if let nativeResult = await checkNativeMacOSAutoCAD() {
            self.current = nativeResult
            cacheDetectionResult(nativeResult)
            return
        }
        
        // Step 2: Check if Parallels is running
        guard await isParallelsDesktopRunning() else {
            self.current = .notRunning
            cacheDetectionResult(.notRunning)
            return
        }
        
        print("[AutoCADEnvironmentDetector] Parallels Desktop detected, scanning for Windows VM...")
        
        // Step 3: Check for Windows VM with AutoCAD (network scan)
        if let parallelsResult = await checkParallelsWindowsVM() {
            self.current = parallelsResult
            cacheDetectionResult(parallelsResult)
            return
        }
        
        // No match found
        self.current = .unknown
        cacheDetectionResult(.unknown)
    }
    
    // MARK: - Manual Override
    
    private func checkManualOverride() -> AutoCADEnvironment? {
        guard let override = UserDefaults.standard.string(forKey: overrideKey) else {
            return nil
        }
        
        print("[AutoCADEnvironmentDetector] Using manual override: \(override)")
        
        switch override.lowercased() {
        case "native":
            return .nativeMac(version: nil)
        case "disabled":
            return .notRunning
        default:
            if override.hasPrefix("parallels:") {
                let ip = String(override.dropFirst("parallels:".count))
                return .parallelsWindows(vmIP: ip)
            }
            return nil
        }
    }
    
    // MARK: - Step 1: Native macOS Detection
    
    private func checkNativeMacOSAutoCAD() async -> AutoCADEnvironment? {
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            // Check bundle ID
            if let bundleID = app.bundleIdentifier {
                if bundleID.lowercased().hasPrefix("com.autodesk.autocad") {
                    let version = extractVersion(from: app)
                    print("[AutoCADEnvironmentDetector] Found native macOS AutoCAD: \(bundleID) v\(version ?? "unknown")")
                    return .nativeMac(version: version)
                }
            }
            
            // Check process name
            if let processName = app.localizedName {
                if processName.lowercased().contains("autocad") && 
                   !processName.lowercased().contains("parallels") {
                    let version = extractVersion(from: app)
                    print("[AutoCADEnvironmentDetector] Found native macOS AutoCAD: \(processName) v\(version ?? "unknown")")
                    return .nativeMac(version: version)
                }
            }
        }
        
        return nil
    }
    
    /// Extract version from app bundle
    private func extractVersion(from app: NSRunningApplication) -> String? {
        guard let bundleURL = app.bundleURL else { return nil }
        guard let bundle = Bundle(url: bundleURL) else { return nil }
        
        // Try short version string first (e.g., "2025.1")
        if let shortVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            return shortVersion
        }
        
        // Fallback to build version
        if let buildVersion = bundle.infoDictionary?["CFBundleVersion"] as? String {
            return buildVersion
        }
        
        return nil
    }
    
    // MARK: - Step 2: Parallels Desktop Detection
    
    private func isParallelsDesktopRunning() async -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            // Check bundle ID
            if let bundleID = app.bundleIdentifier {
                if bundleID.lowercased() == "com.parallels.desktop.console" {
                    print("[AutoCADEnvironmentDetector] Found Parallels Desktop")
                    return true
                }
            }
            
            // Check process name
            if let processName = app.localizedName {
                if processName.lowercased().contains("parallels") {
                    print("[AutoCADEnvironmentDetector] Found Parallels process: \(processName)")
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Step 3: Windows VM with AutoCAD Detection
    
    private func checkParallelsWindowsVM() async -> AutoCADEnvironment? {
        // Scan both Parallels network ranges
        for networkPrefix in parallelsNetworks {
            print("[AutoCADEnvironmentDetector] Scanning network range: \(networkPrefix).0/24")
            
            if let foundIP = await scanNetworkRange(networkPrefix) {
                print("[AutoCADEnvironmentDetector] ✅ Found Windows VM with AutoCAD at: \(foundIP)")
                return .parallelsWindows(vmIP: foundIP)
            }
        }
        
        return nil
    }
    
    /// Scan a /24 network for host with open AutoCAD port
    /// Network prefix: e.g., "10.211.55"
    private func scanNetworkRange(_ networkPrefix: String) async -> String? {
        // Scan from .1 to .254 (skip .0 and .255)
        // Use concurrent scanning with a semaphore to limit concurrent connections
        let semaphore = DispatchSemaphore(value: 10)  // Max 10 concurrent checks
        var foundIP: String?
        
        await withTaskGroup(of: String?.self) { group in
            for hostNumber in 1...254 {
                let ip = "\(networkPrefix).\(hostNumber)"
                
                group.addTask {
                    semaphore.wait()
                    defer { semaphore.signal() }
                    
                    return await self.checkHostAutoCAD(ip)
                }
            }
            
            // Collect results and stop on first match
            for await result in group {
                if let ip = result {
                    foundIP = ip
                    group.cancelAll()
                    break
                }
            }
        }
        
        return foundIP
    }
    
    /// Check if a specific host has AutoCAD listening on port 19848
    private func checkHostAutoCAD(_ ip: String) async -> String? {
        let result = await withTimeoutSeconds(tcpTimeout) {
            await self.checkPortOpen(ip: ip, port: self.autocadWindowsPort)
        }
        
        if result {
            return ip
        }
        return nil
    }
    
    /// Test if a TCP port is open on a host
    private func checkPortOpen(ip: String, port: Int) async -> Bool {
        return await withCheckedContinuation { continuation in
            let host = ip
            let service = NetService(domain: "local.", type: "_tcp", name: ip, port: Int32(port))
            
            // Use simpler TCP socket approach
            DispatchQueue.global().async {
                var socketfd: Int32 = -1
                var hints: addrinfo = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_socktype = SOCK_STREAM
                
                var res: UnsafeMutablePointer<addrinfo>?
                let portString = String(port)
                
                guard getaddrinfo(host, portString, &hints, &res) == 0 else {
                    continuation.resume(returning: false)
                    return
                }
                
                defer { freeaddrinfo(res) }
                
                guard let addr = res else {
                    continuation.resume(returning: false)
                    return
                }
                
                socketfd = socket(addr.pointee.ai_family, addr.pointee.ai_socktype, addr.pointee.ai_protocol)
                guard socketfd >= 0 else {
                    continuation.resume(returning: false)
                    return
                }
                
                defer { close(socketfd) }
                
                // Set non-blocking mode for timeout
                fcntl(socketfd, F_SETFL, O_NONBLOCK)
                
                // Attempt connect
                let connectResult = connect(socketfd, addr.pointee.ai_addr, addr.pointee.ai_addrlen)
                
                if connectResult == 0 {
                    // Connected immediately
                    continuation.resume(returning: true)
                    return
                }
                
                // Check if connection is in progress
                if errno == EINPROGRESS {
                    // Wait for completion with timeout
                    var timeout = timeval()
                    timeout.tv_sec = 0
                    timeout.tv_usec = Int(self.tcpTimeout * 1_000_000)  // Convert to microseconds
                    
                    var writefds = fd_set()
                    FD_ZERO(&writefds)
                    FD_SET(socketfd, &writefds)
                    
                    let selectResult = select(socketfd + 1, nil, &writefds, nil, &timeout)
                    
                    if selectResult > 0 && FD_ISSET(socketfd, &writefds) {
                        // Check connection status
                        var optval: Int32 = 0
                        var optlen = socklen_t(MemoryLayout<Int32>.size)
                        
                        if getsockopt(socketfd, SOL_SOCKET, SO_ERROR, &optval, &optlen) == 0 && optval == 0 {
                            continuation.resume(returning: true)
                            return
                        }
                    }
                }
                
                continuation.resume(returning: false)
            }
        }
    }
    
    /// Execute a task with timeout
    private func withTimeoutSeconds<T>(_ seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
        return await withTaskGroup(of: T?.self) { group in
            let task = group.addTaskUnstructured {
                await operation()
            }
            
            group.addTaskUnstructured {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                task.cancel()
                return nil
            }
            
            for await result in group {
                if let value = result {
                    return value
                }
            }
            
            return nil
        }
    }
    
    // MARK: - Workspace Notifications
    
    private func setupWorkspaceNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        
        workspaceObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            
            let bundleID = app.bundleIdentifier ?? ""
            let processName = app.localizedName ?? ""
            
            // Re-detect if AutoCAD or Parallels launched
            if bundleID.lowercased().contains("autocad") ||
               bundleID.lowercased().contains("parallels") ||
               processName.lowercased().contains("autocad") ||
               processName.lowercased().contains("parallels") {
                print("[AutoCADEnvironmentDetector] App launched: \(processName), re-detecting...")
                Task {
                    await self?.performDetection()
                }
            }
        }
    }
    
    // MARK: - Caching
    
    private func cacheDetectionResult(_ environment: AutoCADEnvironment) {
        let timestamp = Date().timeIntervalSince1970
        UserDefaults.standard.set(timestamp, forKey: lastDetectionKey)
    }
    
    deinit {
        stopDetection()
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

// MARK: - Darwin Imports (for socket operations)
import Darwin

private func fcntl(_ fd: Int32, _ cmd: Int32, _ flags: Int32) -> Int32 {
    Darwin.fcntl(fd, cmd, flags)
}

private let O_NONBLOCK = Int32(4)
private let F_SETFL = Int32(4)
private let EINPROGRESS = Int32(36)
