import SwiftUI

/// Modal overlay for capturing keyboard/mouse input and converting to readable event descriptions
/// Displays a prominent message with countdown timer while listening for user input
struct CaptureOverlay: View {
    @Environment(\.dismiss) var dismiss
    var onCapture: (String) -> Void
    
    @ObservedObject private var keyMouseMonitor = KeyMouseMonitor.shared
    @State private var countdownSeconds: Int = 10
    @State private var countdownTimer: Timer?
    @State private var capturedEvent: String?
    @State private var isProcessing = false
    
    var body: some View {
        ZStack {
            // Semi-transparent dark background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Main capture message
                VStack(spacing: 16) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.cyan)
                    
                    Text("Press key or perform mouse action now…")
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .foregroundStyle(.primary)
                    
                    Text("Listen for keyboard, mouse movement, click, or scroll")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(.secondary)
                }
                
                // Countdown timer with visual feedback
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                            .frame(width: 100, height: 100)
                        
                        Circle()
                            .trim(from: 0, to: Double(countdownSeconds) / 10.0)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [.cyan, .blue]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear, value: countdownSeconds)
                        
                        VStack(spacing: 4) {
                            Text("\(countdownSeconds)")
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundStyle(.cyan)
                            Text("seconds")
                                .font(.system(size: 11, weight: .medium, design: .default))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Status text
                    if let event = capturedEvent {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            
                            Text("Captured: \(event)")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                        .padding(12)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                // Cancel button
                Button(role: .cancel) {
                    stopCapture()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cancel")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color.red.opacity(0.2))
                    .foregroundStyle(.red)
                    .cornerRadius(8)
                }
            }
            .padding(32)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(16)
            .shadow(radius: 16)
            .frame(maxWidth: 400)
        }
        .onAppear {
            startCapture()
        }
        .onDisappear {
            stopCapture()
        }
        .onChange(of: keyMouseMonitor.lastEvent) { oldValue, newValue in
            if let eventDescription = newValue, !isProcessing {
                captureEvent(eventDescription)
            }
        }
    }
    
    private func startCapture() {
        countdownSeconds = 10
        startCountdown()
    }
    
    private func startCountdown() {
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            DispatchQueue.main.async {
                if self.countdownSeconds > 0 {
                    self.countdownSeconds -= 1
                } else {
                    self.stopCapture()
                    self.dismiss()
                }
            }
        }
    }
    
    private func captureEvent(_ eventDescription: String) {
        isProcessing = true
        capturedEvent = eventDescription
        countdownTimer?.invalidate()
        
        // Brief delay to show captured event
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            stopCapture()
            onCapture(eventDescription)
            dismiss()
        }
    }
    
    private func stopCapture() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
}

// MARK: - Preview

#Preview {
    CaptureOverlay { event in
        print("Captured: \(event)")
    }
}
