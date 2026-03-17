import SwiftUI
import Combine

enum OverlayItemKind {
    case keyboard
    case leftClick
    case rightClick
    case middleClick
    case scrollUp
    case scrollDown
    case scrollLeft
    case scrollRight
    case dragUp
    case dragDown
    case dragLeft
    case dragRight
}

struct OverlayItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let kind: OverlayItemKind
    var timestamp: Date
    var direction: OverlayItemKind?

    static func == (lhs: OverlayItem, rhs: OverlayItem) -> Bool {
        lhs.id == rhs.id
    }
}

final class OverlayViewModel: ObservableObject {
    @Published var items: [OverlayItem] = []

    private var cancellables: Set<AnyCancellable> = []
    private var timerCancellable: AnyCancellable?

    init() {
        // Observe lastEvent on KeyMouseMonitor.shared
        KeyMouseMonitor.shared.$lastEvent
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] eventString in
                self?.process(eventString)
            }
            .store(in: &cancellables)

        // Timer to clear expired items every 0.1s on main run loop
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.clearExpired()
            }
    }

    private func process(_ eventString: String) {
        // Determine kind and text from event string
        let text = eventString.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = text.uppercased()

        if upper.contains("CLICK") {
            if upper.contains("LEFT") {
                pushMouse(kind: .leftClick, text: text)
            } else if upper.contains("RIGHT") {
                pushMouse(kind: .rightClick, text: text)
            } else if upper.contains("MIDDLE") {
                pushMouse(kind: .middleClick, text: text)
            } else {
                pushMouse(kind: .leftClick, text: text)
            }
        } else if upper.contains("DRAG") {
            if upper.contains("UP") {
                pushMouse(kind: .dragUp, text: text)
            } else if upper.contains("DOWN") {
                pushMouse(kind: .dragDown, text: text)
            } else if upper.contains("LEFT") {
                pushMouse(kind: .dragLeft, text: text)
            } else if upper.contains("RIGHT") {
                pushMouse(kind: .dragRight, text: text)
            } else {
                pushMouse(kind: .dragRight, text: text)
            }
        } else if upper.contains("SCROLL") {
            if upper.contains("UP") || upper.contains("↑") {
                pushMouse(kind: .scrollUp, text: text)
            } else if upper.contains("DOWN") || upper.contains("↓") {
                pushMouse(kind: .scrollDown, text: text)
            } else if upper.contains("LEFT") || upper.contains("←") {
                pushMouse(kind: .scrollLeft, text: text)
            } else if upper.contains("RIGHT") || upper.contains("→") {
                pushMouse(kind: .scrollRight, text: text)
            } else {
                pushMouse(kind: .scrollUp, text: text)
            }
        } else {
            // Assume keyboard
            pushKeyboard(text: text)
        }
    }

    func pushKeyboard(text: String) {
        let now = Date()
        // Check if last keyboard item matches text, update timestamp if so
        if let lastIdx = items.lastIndex(where: { $0.kind == .keyboard && $0.text == text }) {
            items[lastIdx].timestamp = now
        } else {
            let item = OverlayItem(id: UUID(), text: text, kind: .keyboard, timestamp: now, direction: nil)
            items.append(item)
        }
    }

    func pushMouse(kind: OverlayItemKind, text: String) {
        let now = Date()
        // For mouse events, if same kind and text is similar, update timestamp
        if let lastIdx = items.lastIndex(where: { $0.kind == kind && $0.text == text }) {
            items[lastIdx].timestamp = now
        } else {
            let item = OverlayItem(id: UUID(), text: text, kind: kind, timestamp: now, direction: nil)
            items.append(item)
        }
    }

    func clearExpired() {
        let now = Date()
        // keyboard items expire after 1.5 seconds, others after 2 seconds
        items.removeAll { item in
            let age = now.timeIntervalSince(item.timestamp)
            switch item.kind {
            case .keyboard:
                return age > 1.5
            default:
                return age > 2.0
            }
        }
    }
}

struct OverlayView: View {
    @StateObject private var model = OverlayViewModel()
    @AppStorage("overlay.opacity") private var bgOpacity: Double = 0.5
    @State private var isHidden: Bool = false

    private func color(for kind: OverlayItemKind) -> Color {
        switch kind {
        case .leftClick: return .blue
        case .rightClick: return .red
        case .middleClick: return .purple
        case .keyboard: return .cyan
        case .scrollUp, .scrollDown, .scrollLeft, .scrollRight: return .mint
        case .dragUp, .dragDown, .dragLeft, .dragRight: return .orange
        }
    }

    private func iconName(for kind: OverlayItemKind) -> String {
        switch kind {
        case .keyboard: return "keyboard"
        case .leftClick: return "cursorarrow.click"
        case .rightClick: return "cursorarrow.click"
        case .middleClick: return "cursorarrow.click"
        case .scrollUp: return "arrow.up"
        case .scrollDown: return "arrow.down"
        case .scrollLeft: return "arrow.left"
        case .scrollRight: return "arrow.right"
        case .dragUp: return "cursorarrow.motionlines"
        case .dragDown: return "cursorarrow.motionlines"
        case .dragLeft: return "cursorarrow.motionlines"
        case .dragRight: return "cursorarrow.motionlines"
        }
    }

    private func iconRotation(for kind: OverlayItemKind) -> Angle {
        switch kind {
        case .dragUp: return Angle(degrees: 0)
        case .dragDown: return Angle(degrees: 180)
        case .dragLeft: return Angle(degrees: -90)
        case .dragRight: return Angle(degrees: 90)
        default: return .zero
        }
    }

    var body: some View {
        ZStack {
            if isHidden {
                VStack {
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 60, height: 30)
                        .overlay(
                            Button(action: { withAnimation { isHidden = false } }) {
                                Text("Show")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                            }
                        )
                        .shadow(radius: 4)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Spacer()
                        Button(action: { withAnimation { isHidden = true } }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    ForEach(model.items) { item in
                        HStack(spacing: 8) {
                            Image(systemName: iconName(for: item.kind))
                                .rotationEffect(iconRotation(for: item.kind))
                                .foregroundColor(color(for: item.kind))
                                .font(.title2)
                                .frame(width: 28)

                            Text(item.text)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(color(for: item.kind))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Spacer()
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.4))
                        )
                        .transition(
                            .move(edge: .top)
                            .combined(with: .opacity)
                        )
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(bgOpacity))
                        .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 4)
                )
                .padding()
                .animation(.easeInOut(duration: 0.3), value: model.items)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: 320)
        .onAppear {
            // Ensure opacity has default value if not set
            if bgOpacity == 0 { bgOpacity = 0.5 }
        }
    }
}

struct OverlayView_Previews: PreviewProvider {
    struct Container: View {
        @StateObject private var model = OverlayViewModel()

        var body: some View {
            OverlayView()
                .onAppear {
                    let now = Date()
                    model.items = [
                        OverlayItem(id: UUID(), text: "A", kind: .keyboard, timestamp: now, direction: nil),
                        OverlayItem(id: UUID(), text: "Left Click", kind: .leftClick, timestamp: now, direction: nil),
                        OverlayItem(id: UUID(), text: "Right Click", kind: .rightClick, timestamp: now, direction: nil),
                        OverlayItem(id: UUID(), text: "Middle Click", kind: .middleClick, timestamp: now, direction: nil),
                        OverlayItem(id: UUID(), text: "Scroll Up", kind: .scrollUp, timestamp: now, direction: nil),
                        OverlayItem(id: UUID(), text: "Scroll Down", kind: .scrollDown, timestamp: now, direction: nil),
                        OverlayItem(id: UUID(), text: "Drag Left", kind: .dragLeft, timestamp: now, direction: nil),
                    ]
                }
        }
    }

    static var previews: some View {
        Container()
            .preferredColorScheme(.dark)
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
