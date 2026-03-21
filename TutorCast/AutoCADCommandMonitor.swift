// AutoCADCommandMonitor.swift
// TutorCast
//
// High-level abstraction for reading AutoCAD's active command and subcommand.
// Automatically detects whether AutoCAD is running natively on macOS or
// inside Parallels Desktop (Windows VM), and routes to the appropriate reader.
//
// Responsibilities:
//   • Detect which AutoCAD environment is active
//   • Maintain references to both reader implementations
//   • Poll or listen for command state changes
//   • Publish commandName and subcommandText for overlay display
//   • Handle errors gracefully (fallback to keyboard-only mode if needed)

import Foundation
import Combine

@MainActor
final class AutoCADCommandMonitor: ObservableObject {
    static let shared = AutoCADCommandMonitor()

    // MARK: - Published Properties
    
    /// The current command name (e.g., "LINE", "OFFSET", "HATCH")
    @Published var commandName: String = ""
    
    /// The current subcommand or prompt (e.g., "Specify first point:", "Select objects:")
    @Published var subcommandText: String = ""
    
    /// Whether we are actively reading command state (true = success, false = fallback to keyboard-only)
    @Published var isMonitoring: Bool = false
    
    /// Which environment is detected (useful for debugging / UI feedback)
    @Published var detectedEnvironment: AutoCADEnvironment = .unknown
    
    // MARK: - Private State
    
    private var nativeReader: NativeMacOSAutoCADReader?
    private var parallelsReader: ParallelsWindowsAutoCADReader?
    
    private var monitoringTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // Polling interval for command state updates (in seconds)
    private let pollInterval: TimeInterval = 0.1  // 100ms for responsive overlay
    
    private init() {}
    
    // MARK: - Lifecycle
    
    /// Start monitoring AutoCAD's command state
    func start() {
        print("[AutoCADCommandMonitor] Starting command monitor...")
        
        // Initialize both readers
        nativeReader = NativeMacOSAutoCADReader()
        parallelsReader = ParallelsWindowsAutoCADReader()
        
        // Detect environment and start appropriate reader
        Task {
            await detectAndStartMonitoring()
        }
    }
    
    /// Stop monitoring
    func stop() {
        print("[AutoCADCommandMonitor] Stopping command monitor...")
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        isMonitoring = false
        commandName = ""
        subcommandText = ""
    }
    
    // MARK: - Environment Detection & Monitoring
    
    private func detectAndStartMonitoring() async {
        // Try native AutoCAD first
        if await nativeReader?.isAutoCADRunning() ?? false {
            detectedEnvironment = .nativeMacOS
            print("[AutoCADCommandMonitor] ✅ Detected native macOS AutoCAD")
            startNativeMonitoring()
            return
        }
        
        // Try Parallels AutoCAD
        if await parallelsReader?.isAutoCADRunning() ?? false {
            detectedEnvironment = .parallelsWindows
            print("[AutoCADCommandMonitor] ✅ Detected AutoCAD in Parallels Desktop")
            startParallelsMonitoring()
            return
        }
        
        // No AutoCAD detected
        detectedEnvironment = .unknown
        print("[AutoCADCommandMonitor] ⚠️  No AutoCAD detected. Falling back to keyboard-only mode.")
        isMonitoring = false
    }
    
    private func startNativeMonitoring() {
        guard let reader = nativeReader else { return }
        
        isMonitoring = true
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task {
                guard let self else { return }
                
                do {
                    let state = try await reader.readCommandState()
                    
                    DispatchQueue.main.async {
                        self.commandName = state.commandName
                        self.subcommandText = state.subcommandText
                    }
                    
                } catch {
                    print("[AutoCADCommandMonitor] Error reading native AutoCAD state: \(error)")
                    // Keep the last known state; don't clear
                }
            }
        }
    }
    
    private func startParallelsMonitoring() {
        guard let reader = parallelsReader else { return }
        
        isMonitoring = true
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task {
                guard let self else { return }
                
                do {
                    let state = try await reader.readCommandState()
                    
                    DispatchQueue.main.async {
                        self.commandName = state.commandName
                        self.subcommandText = state.subcommandText
                    }
                    
                } catch {
                    print("[AutoCADCommandMonitor] Error reading Parallels AutoCAD state: \(error)")
                    // Keep the last known state; don't clear
                }
            }
        }
    }
    
    /// Re-detect environment (useful if user switches between native and Parallels)
    func redetectEnvironment() async {
        stop()
        await detectAndStartMonitoring()
    }
    
    deinit {
        stop()
    }
}

// MARK: - Supporting Types

/// Represents the detected AutoCAD environment
enum AutoCADEnvironment: Equatable {
    case nativeMacOS
    case parallelsWindows
    case unknown
}

/// The command state read from AutoCAD at a given moment
struct AutoCADCommandState {
    let commandName: String        // "LINE", "OFFSET", "HATCH", etc. (empty if no command active)
    let subcommandText: String     // "Specify first point:", "Select objects:", etc.
}

// MARK: - Protocol for Reader Implementations

/// Abstract interface for AutoCAD command readers
protocol AutoCADReader: AnyObject {
    /// Check if AutoCAD is currently running
    func isAutoCADRunning() async -> Bool
    
    /// Read the current command state
    func readCommandState() async throws -> AutoCADCommandState
}
