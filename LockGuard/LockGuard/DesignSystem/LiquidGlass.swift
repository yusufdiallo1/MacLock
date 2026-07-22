//
//  LiquidGlass.swift
//  LockGuard — DesignSystem
//
//  The reusable Liquid Glass layer. Every frosted surface in the app goes
//  through `.lgGlass(_:)` so glass looks and behaves the same everywhere and
//  the whole system can be tuned from one place (Prompt 37's Appearance pane
//  modulates `GlassConfig`).
//
//  Two rendering paths, gated on OS — never assume:
//   • macOS 26+  → Apple's real Liquid Glass (`.glassEffect`), which already
//                  refracts and reacts to what's behind it.
//   • macOS 14–15 → an `NSVisualEffectView` frost dressed with the same
//                  specular treatment, so it still reads as glass.
//
//  Accessibility gates sit ABOVE both paths: Reduce Transparency swaps glass
//  for a solid elevated surface; Increase Contrast thickens the strokes.
//
//  Presets (spec): .glassPanel (sidebars/settings), .glassCard (auth/dashboard
//  cards), .glassBar (menu-bar popover, toolbars).
//

import SwiftUI
import AppKit

// MARK: - Presets & config

/// The three semantic glass surfaces. Each resolves to a `GlassConfig`.
enum LGGlassPreset {
    case panel   // sidebars, settings columns — quiet, large radius
    case card    // auth overlay, dashboard cards — elevated, accent-leaning
    case bar     // menu-bar popover, toolbars — neutral

    var config: GlassConfig {
        switch self {
        case .panel:
            return GlassConfig(cornerRadius: 18, material: .underWindowBackground,
                               tint: Color.lgBgElevated.opacity(0.22),
                               shadowRadius: 18, shadowY: 10)
        case .card:
            return GlassConfig(cornerRadius: 24, material: .hudWindow,
                               tint: Color.lgAccentPrimary.opacity(0.10),
                               shadowRadius: 34, shadowY: 20)
        case .bar:
            return GlassConfig(cornerRadius: 20, material: .hudWindow,
                               tint: Color.lgBgBase.opacity(0.28),
                               shadowRadius: 22, shadowY: 12)
        }
    }
}

/// The tunable knobs behind a preset. Prompt 37's glass-intensity slider will
/// scale `tint` opacity and, on the fallback path, the material.
struct GlassConfig {
    var cornerRadius: CGFloat
    var material: NSVisualEffectView.Material
    var tint: Color
    var shadowRadius: CGFloat
    var shadowY: CGFloat
}

// MARK: - The core modifier

/// Applies a Liquid Glass surface behind the content, honoring the OS glass
/// capability and the accessibility settings.
struct LGGlass: ViewModifier {
    var preset: LGGlassPreset
    var interactive: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var cfg: GlassConfig { preset.config }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cfg.cornerRadius, style: .continuous)
    }
    /// Increase Contrast thickens every stroke in the system.
    private var strokeWidth: CGFloat { contrast == .increased ? 1.5 : 1 }

    func body(content: Content) -> some View {
        if reduceTransparency {
            // No glass, no sheen: a solid elevated surface with a hairline (or a
            // stronger stroke under Increase Contrast) so structure is still read.
            content
                .background(shape.fill(Color.lgBgElevated))
                .overlay(shape.strokeBorder(Color.lgHairline.opacity(contrast == .increased ? 0.9 : 1),
                                            lineWidth: strokeWidth))
        } else {
            glassBody(content)
                .modifier(InteractiveSheen(shape: shape, enabled: interactive))
                .shadow(color: .black.opacity(0.5), radius: cfg.shadowRadius, y: cfg.shadowY)
        }
    }

    @ViewBuilder
    private func glassBody(_ content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let glass: Glass = interactive
                ? .regular.tint(cfg.tint).interactive()
                : .regular.tint(cfg.tint)
            content
                .glassEffect(glass, in: .rect(cornerRadius: cfg.cornerRadius))
                .overlay(SpecularOverlay(shape: shape, strokeWidth: strokeWidth))
        } else {
            content
                .background(NSGlassView(material: cfg.material).clipShape(shape))
                .overlay(shape.fill(cfg.tint))
                .overlay(SpecularOverlay(shape: shape, strokeWidth: strokeWidth))
        }
    }
}

// MARK: - Specular treatment (shared by both paths)

/// Enriches any glass surface with the same lit-from-above look: a thin white
/// top highlight fading down, the conic `glassBorder` rim, and a soft inner
/// shadow for depth. Applied over both the native and fallback paths so glass
/// is visually consistent across OS versions.
private struct SpecularOverlay: View {
    let shape: RoundedRectangle
    var strokeWidth: CGFloat = 1

    var body: some View {
        ZStack {
            // Top highlight: white @ ~12% at the top, fading to clear.
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.12), Color.white.opacity(0)],
                    startPoint: .top, endPoint: .center
                )
            )
            // Conic purple→blue→gold rim.
            shape.strokeBorder(LGGradient.glassBorder, lineWidth: strokeWidth)
            // Inner shadow: a dark inner stroke, blurred and masked to the shape,
            // reads as depth at the bottom edge.
            shape
                .stroke(Color.black.opacity(0.35), lineWidth: 3)
                .blur(radius: 3)
                .mask(shape.fill(LinearGradient(
                    colors: [.clear, .black], startPoint: .center, endPoint: .bottom)))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Fallback frost (macOS 14–15)

/// Wraps `NSVisualEffectView` so the fallback path frosts what's behind the
/// window the way real glass does. `behindWindow` blends with the desktop /
/// app below; `.active` keeps it frosted even when the window isn't key.
private struct NSGlassView: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

// MARK: - Interactive sheen

/// On hover, a soft radial sheen follows the cursor across the glass; on press,
/// the surface springs to 0.98. Both are suppressed under Reduce Motion. The
/// sheen never intercepts hits. Only applied when a preset is `interactive`.
private struct InteractiveSheen: ViewModifier {
    let shape: RoundedRectangle
    var enabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoverPoint: CGPoint?
    @State private var pressed = false

    func body(content: Content) -> some View {
        guard enabled, !reduceMotion else { return AnyView(content) }
        return AnyView(
            content
                .overlay(sheen)
                .scaleEffect(pressed ? 0.98 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): hoverPoint = p
                    case .ended:         hoverPoint = nil
                    }
                }
                // Track press without stealing the content's own taps/buttons.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in pressed = true }
                        .onEnded { _ in pressed = false }
                )
        )
    }

    @ViewBuilder
    private var sheen: some View {
        if let p = hoverPoint {
            GeometryReader { geo in
                RadialGradient(
                    colors: [Color.white.opacity(0.10), Color.white.opacity(0)],
                    center: UnitPoint(x: p.x / max(geo.size.width, 1),
                                      y: p.y / max(geo.size.height, 1)),
                    startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * 0.6
                )
            }
            .clipShape(shape)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

// MARK: - Button styles (.glass / .glassProminent)

/// Glass button: native `.glass` on 26+, a glass-chip capsule on the fallback.
struct LGGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            AnyView(configuration.label.buttonStyle(.glass))
        } else {
            AnyView(
                configuration.label
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .modifier(LGGlass(preset: .bar, interactive: true))
                    .clipShape(Capsule())
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
        }
    }
}

/// Prominent glass button: native `.glassProminent` on 26+, an accent-filled
/// capsule on the fallback.
struct LGGlassProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            AnyView(configuration.label.buttonStyle(.glassProminent))
        } else {
            AnyView(
                configuration.label
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(Color.lgAccentPrimary))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
        }
    }
}

extension ButtonStyle where Self == LGGlassButtonStyle {
    static var lgGlass: LGGlassButtonStyle { LGGlassButtonStyle() }
}
extension ButtonStyle where Self == LGGlassProminentButtonStyle {
    static var lgGlassProminent: LGGlassProminentButtonStyle { LGGlassProminentButtonStyle() }
}

// MARK: - View entry point

extension View {
    /// Apply a Liquid Glass surface. `interactive` adds the cursor sheen +
    /// press-scale (use for chips/buttons, not static panels).
    func lgGlass(_ preset: LGGlassPreset, interactive: Bool = false) -> some View {
        modifier(LGGlass(preset: preset, interactive: interactive))
    }
}
