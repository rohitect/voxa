import SwiftUI
import AppKit

// MARK: - Window Accessor

/// Inserts an `NSVisualEffectView` behind the SwiftUI content so the entire
/// window gets genuine behind-window vibrancy (desktop bleeds through).
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = WindowEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Subclass that configures the window as soon as the view is attached.
private class WindowEffectView: NSVisualEffectView {
    private var didConfigure = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !didConfigure else { return }
        didConfigure = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
    }
}

// MARK: - Voxa Glass Theme

/// Central design tokens for Voxa's translucent "glass" UI theme.
/// Materials auto-adapt to light/dark mode with no extra logic.
enum VoxaTheme {

    // MARK: Semantic Colors

    /// Subtle overlay for hover states
    static let surfaceOverlay = Color.primary.opacity(0.04)
    /// Stronger overlay for selected/active states
    static let surfaceOverlayActive = Color.accentColor.opacity(0.10)
    /// Separator between sections
    static let separator = Color.primary.opacity(0.08)
    /// Border stroke for cards
    static let borderStroke = Color.primary.opacity(0.06)
    /// Active/focused border stroke
    static let borderStrokeActive = Color.primary.opacity(0.12)
}

// MARK: - Glass Card Modifier

/// Card with material background, corner radius, and subtle border.
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(VoxaTheme.borderStroke, lineWidth: 0.5)
            )
    }
}

/// Input field with thick material and focus ring support.
struct GlassInputModifier: ViewModifier {
    var isFocused: Bool = false
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isFocused ? VoxaTheme.borderStrokeActive : VoxaTheme.borderStroke,
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - View Extensions

extension View {
    /// Apply glass card styling: regular material + rounded corners + border.
    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// Apply glass input styling: thick material + focus ring.
    func glassInput(isFocused: Bool = false, cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassInputModifier(isFocused: isFocused, cornerRadius: cornerRadius))
    }
}
