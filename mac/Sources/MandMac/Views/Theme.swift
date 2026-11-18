import AppKit
import SwiftUI

/// M’AND design tokens (docs/DESIGN_SYSTEM.md): monochrome "chrome". Soft silver gradients, black and white
/// pills, one dark hero card per screen, and metallic icons. No colour is ever the only signal: every state
/// also has words. Motion is springy but honours Reduce Motion.
enum Theme {
    // Ink: the one "accent". Near-black in light mode, near-white in dark mode.
    static let ink = dynamic(light: (0.07, 0.07, 0.08), dark: (0.96, 0.96, 0.97))
    /// Kept for older call sites; the accent is now ink.
    static let accent = ink
    static let positive = ink
    static let caution = dynamic(light: (0.55, 0.36, 0.05), dark: (1.00, 0.78, 0.40))
    static let critical = dynamic(light: (0.70, 0.18, 0.14), dark: (1.00, 0.55, 0.48))
    static let surface = dynamic(light: (0.985, 0.985, 0.99), dark: (0.15, 0.15, 0.16))
    static let surfaceRaised = dynamic(light: (0.93, 0.93, 0.945), dark: (0.21, 0.21, 0.225))
    static let hairline = Color.primary.opacity(0.08)

    /// Page background: a soft silver fade, like brushed metal.
    static let page = LinearGradient(colors: [dynamic(light: (0.95, 0.95, 0.96), dark: (0.10, 0.10, 0.11)),
                                              dynamic(light: (0.82, 0.82, 0.84), dark: (0.03, 0.03, 0.035))],
                                     startPoint: .top, endPoint: .bottom)
    /// Card fill: lit from the top.
    static let card = LinearGradient(colors: [dynamic(light: (1, 1, 1), dark: (0.20, 0.20, 0.215)),
                                              dynamic(light: (0.90, 0.90, 0.915), dark: (0.12, 0.12, 0.13))],
                                     startPoint: .top, endPoint: .bottom)
    /// The dark hero card (always dark, in both modes), with white text.
    static let hero = LinearGradient(colors: [Color(white: 0.20), Color(white: 0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// A thin bright edge on the top of cards, like light catching a bevel.
    static let bevel = LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom)

    // Spacing (4-pt grid)
    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
    }

    // Corner radii: big and friendly
    enum Radius {
        static let small: CGFloat = 10, medium: CGFloat = 18, large: CGFloat = 28
    }

    // Typography: SF Rounded for headings and numbers, regular SF for reading.
    enum Font {
        static let hero = SwiftUI.Font.system(size: 30, weight: .bold, design: .rounded)
        static let title = SwiftUI.Font.system(.title3, design: .rounded).weight(.semibold)
        static let section = SwiftUI.Font.system(.headline, design: .rounded)
        static let body = SwiftUI.Font.body
        static let caption = SwiftUI.Font.caption
        static let numeral = SwiftUI.Font.system(size: 15, weight: .bold, design: .rounded).monospacedDigit()
    }

    static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

/// Metallic fills for icons and orbs.
enum ChromeStyle {
    /// Polished chrome: bright, dark band, bright again.
    static let shine = LinearGradient(colors: [.white, Color(white: 0.62), Color(white: 0.97), Color(white: 0.55)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    /// A darker chrome for icons on light backgrounds.
    static let graphite = LinearGradient(colors: [Color(white: 0.38), Color(white: 0.05), Color(white: 0.30)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Motion

/// State-change animation that respects “Reduce motion”.
struct Motion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: AnyHashable

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: value)
    }
}

/// Cards rise and fade in when a screen opens, one after another.
struct Entrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let order: Int
    /// `State` used directly (the `@State` shorthand needs Xcode's macro plugin).
    private let shownState = State(initialValue: false)

    func body(content: Content) -> some View {
        let shown = shownState.wrappedValue
        return content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .scaleEffect(shown || reduceMotion ? 1 : 0.98)
            .onAppear {
                if reduceMotion { shownState.wrappedValue = true; return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(Double(order) * 0.06)) {
                    shownState.wrappedValue = true
                }
            }
    }
}

extension View {
    func stateAnimation(_ value: some Hashable) -> some View { modifier(Motion(value: AnyHashable(value))) }
    func entrance(_ order: Int = 0) -> some View { modifier(Entrance(order: order)) }
}

// MARK: - Buttons

/// Pill buttons from the design: filled ink ("Subscribe") or outlined ("Follow"). Squishes when pressed.
struct PillButtonStyle: ButtonStyle {
    var prominent = true
    var onDark = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let fill: AnyShapeStyle = prominent
            ? (onDark ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.ink))
            : AnyShapeStyle(Color.clear)
        let text: Color = prominent ? (onDark ? .black : Color(nsColor: .windowBackgroundColor)) : (onDark ? .white : .primary)
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .frame(minHeight: 40)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : (onDark ? Color.white.opacity(0.75) : Color.primary.opacity(0.55)),
                                            lineWidth: 1.2))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillOutline: PillButtonStyle { PillButtonStyle(prominent: false) }
    static var pillOnDark: PillButtonStyle { PillButtonStyle(onDark: true) }
    static var pillOutlineOnDark: PillButtonStyle { PillButtonStyle(prominent: false, onDark: true) }
}
