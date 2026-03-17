import Foundation
import Combine

final class KeyMouseMonitor: ObservableObject {
    static let shared = KeyMouseMonitor()

    // The latest event string observed by the system (e.g., "Left Click", "Scroll Up", or a key like "A").
    @Published public var lastEvent: String? = nil

    private init() {}

    // Helper for testing and previews to feed events into the overlay.
    public func simulate(event: String) {
        if Thread.isMainThread {
            self.lastEvent = event
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.lastEvent = event
            }
        }
    }
}
