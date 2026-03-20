import SwiftUI

/// The floating companion — orb pinned at top-center, chat bubble appears below it.
/// The entire view is always the full panel size; the chat area animates in/out
/// via SwiftUI while the orb stays perfectly still.
struct CompanionView: View {
    private let state = CompanionState.shared
    let panelState: AgentPanelState
    let onDismissChat: () -> Void
    let onNewSession: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Fixed orb at the top
            orbArea

            // Chat bubble below the orb
            if state.isChatExpanded {
                chatBubble
                    .transition(
                        .scale(scale: 0.4, anchor: .top)
                        .combined(with: .opacity)
                        .combined(with: .offset(y: -20))
                    )
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: state.isChatExpanded)
    }

    // MARK: - Orb Area (fixed position, never moves)

    private var orbArea: some View {
        CompanionOrb()
            .overlay(alignment: .bottom) {
                if state.indicatorPhase != .hidden && !state.isChatExpanded {
                    IndicatorPill(phase: state.indicatorPhase)
                        .offset(y: 32)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: state.indicatorPhase)
            .frame(width: 80, height: 80)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    // MARK: - Chat Bubble

    private var chatBubble: some View {
        VStack(spacing: 0) {
            // Tail pointing up toward the orb
            BubbleTail()
                .fill(.ultraThinMaterial)
                .frame(width: 16, height: 10)

            // Chat content
            VStack(spacing: 0) {
                AgentPanelContent(
                    state: panelState,
                    onDismiss: onDismissChat,
                    onNewSession: onNewSession
                )
            }
            .frame(width: 360, height: 400)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 6)
        }
    }
}

// MARK: - Bubble Tail Shape

/// A small triangle pointing upward — the "tail" connecting the chat bubble to the orb.
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: - Companion Orb

struct CompanionOrb: View {
    private let state = CompanionState.shared
    @State private var gearSpinning = false

    var body: some View {
        ZStack {
            Circle()
                .fill(glowColor.opacity(glowOpacity))
                .frame(width: 64, height: 64)
                .blur(radius: 8)

            if case .listening = state.phase {
                PulseRingsView()
                    .frame(width: 64, height: 64)
                    .transition(.opacity)
            }

            if case .processing = state.phase {
                OrbitingParticlesView()
                    .frame(width: 80, height: 80)
                    .transition(.opacity)
            }

            Circle()
                .fill(coreGradient)
                .frame(width: 48, height: 48)
                .scaleEffect(orbScale)
                .modifier(TokenPulseModifier(counter: state.tokenPulseCounter))

            BlinkingEyesView(phase: state.phase)
                .offset(y: -2)

            if case .toolExecution = state.phase {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(gearSpinning ? 360 : 0))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: gearSpinning)
                    .offset(x: 18, y: 18)
                    .transition(.scale.combined(with: .opacity))
                    .onAppear { gearSpinning = true }
                    .onDisappear { gearSpinning = false }
            }
        }
        .frame(width: 80, height: 80)
        .modifier(BreathingModifier())
        .animation(.easeInOut(duration: 0.4), value: state.phase)
    }

    private var coreGradient: RadialGradient {
        switch state.phase {
        case .idle:
            RadialGradient(colors: [.cyan, .blue], center: .center, startRadius: 0, endRadius: 24)
        case .listening:
            RadialGradient(colors: [.green, .teal], center: .center, startRadius: 0, endRadius: 24)
        case .processing:
            RadialGradient(colors: [.orange, .purple], center: .center, startRadius: 0, endRadius: 24)
        case .responding, .toolExecution:
            RadialGradient(colors: [.blue, .indigo], center: .center, startRadius: 0, endRadius: 24)
        }
    }

    private var glowColor: Color {
        switch state.phase {
        case .idle: .cyan
        case .listening: .green
        case .processing: .orange
        case .responding, .toolExecution: .blue
        }
    }

    private var glowOpacity: Double {
        switch state.phase {
        case .idle: 0.2
        case .listening: 0.4
        case .processing: 0.3
        case .responding, .toolExecution: 0.4
        }
    }

    private var orbScale: CGFloat {
        switch state.phase {
        case .listening: 1.05
        default: 1.0
        }
    }
}

// MARK: - Indicator Pill

private struct IndicatorPill: View {
    let phase: CompanionState.IndicatorPhase

    var body: some View {
        HStack(spacing: 6) {
            if phase == .recording {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .modifier(IndicatorPulse())
            } else {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 11, weight: .medium))
            }

            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .fixedSize()
    }

    private var iconName: String {
        switch phase {
        case .processing: "hourglass"
        case .done: "checkmark.circle.fill"
        default: ""
        }
    }

    private var iconColor: Color {
        switch phase {
        case .processing: .orange
        case .done: .green
        default: .clear
        }
    }

    private var label: String {
        switch phase {
        case .recording: "Listening..."
        case .processing: "Processing..."
        case .done: "Done"
        case .hidden: ""
        }
    }
}

private struct IndicatorPulse: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.3 : 1.0)
            .opacity(pulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}
