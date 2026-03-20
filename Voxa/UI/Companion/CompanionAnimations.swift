import SwiftUI

// MARK: - Breathing Modifier (Idle float + scale)

struct BreathingModifier: ViewModifier {
    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let floatY = sin(t * 2.4 * .pi) * 3.0  // 1.2Hz, 3pt bob
            let scale = 1.0 + sin(t * 1.6 * .pi) * 0.02  // 0.8Hz, ±2%
            content
                .offset(y: floatY)
                .scaleEffect(scale)
        }
    }
}

// MARK: - Pulse Rings (Listening)

struct PulseRingsView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.green.opacity(0.6), lineWidth: 1.5)
                    .scaleEffect(animate ? 1.8 : 1.0)
                    .opacity(animate ? 0.0 : 0.6)
                    .animation(
                        .easeOut(duration: 1.5)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.5),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
        .onDisappear { animate = false }
    }
}

// MARK: - Orbiting Particles (Processing)

struct OrbitingParticlesView: View {
    let radius: CGFloat = 28
    let particleCount = 4

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<particleCount {
                    let angle = t * 2.0 + Double(i) * (.pi * 2 / Double(particleCount))
                    let x = center.x + cos(angle) * radius
                    let y = center.y + sin(angle) * radius
                    let rect = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.orange.opacity(0.8))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Token Pulse Modifier (Responding)

struct TokenPulseModifier: ViewModifier {
    let counter: Int

    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0)
            .animation(.spring(response: 0.15, dampingFraction: 0.5), value: counter)
            .onChange(of: counter) { _, _ in
                // The animation system handles the spring bounce via the value change
            }
    }
}

// MARK: - Blinking Eyes

struct BlinkingEyesView: View {
    let phase: CompanionState.Phase
    @State private var eyeHeight: CGFloat = 7
    @State private var blinkTimer: Timer?
    @State private var lookOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            Ellipse()
                .fill(.white.opacity(0.9))
                .frame(width: 5, height: eyeHeight)
                .offset(x: lookOffset)
            Ellipse()
                .fill(.white.opacity(0.9))
                .frame(width: 5, height: eyeHeight)
                .offset(x: lookOffset)
        }
        .onAppear { startBlinking() }
        .onDisappear { blinkTimer?.invalidate() }
        .onChange(of: phase) { _, newPhase in
            if case .processing = newPhase {
                startLooking()
            } else {
                lookOffset = 0
            }
        }
    }

    private func startBlinking() {
        scheduleBlink()
    }

    private func scheduleBlink() {
        let interval = Double.random(in: 3.0...5.0)
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.12)) {
                    eyeHeight = 1
                }
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeInOut(duration: 0.12)) {
                    eyeHeight = 7
                }
                scheduleBlink()
            }
        }
    }

    private func startLooking() {
        // Sine-wave look left-right during processing is handled in the parent via TimelineView
        // Here we just reset when not processing
    }
}

// MARK: - Generic Pulse Modifier (used by AgentChatPage, AgentPanelContent, etc.)

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
