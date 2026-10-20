import AppKit
import SwiftUI

/// M’AND design tokens (docs/DESIGN_SYSTEM.md). Graphite surfaces, one mint accent, restrained motion.
enum Theme {
    // Colour
    static let accent = dynamic(light: (0.18, 0.62, 0.45), dark: (0.36, 0.84, 0.62))
    static let positive = accent
    static let caution = dynamic(light: (0.80, 0.47, 0.10), dark: (1.00, 0.66, 0.30))
    static let critical = dynamic(light: (0.77, 0.27, 0.18), dark: (1.00, 0.54, 0.45))
    static let surface = dynamic(light: (1.00, 1.00, 1.00), dark: (0.11, 0.12, 0.14))
    static let surfaceRaised = dynamic(light: (0.96, 0.97, 0.98), dark: (0.15, 0.16, 0.19))
    static let hairline = Color.primary.opacity(0.08)

    // Spacing (4-pt grid)
    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
    }

    // Corner radii
    enum Radius {
        static let small: CGFloat = 8, medium: CGFloat = 12, large: CGFloat = 18
    }

    // Typography (SF; rounded only for numerals such as battery)
    enum Font {
        static let hero = SwiftUI.Font.system(size: 26, weight: .semibold)
        static let title = SwiftUI.Font.title3.weight(.semibold)
        static let section = SwiftUI.Font.headline
        static let body = SwiftUI.Font.body
        static let caption = SwiftUI.Font.caption
        static let numeral = SwiftUI.Font.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit()
    }

    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

/// State-change animation that respects “Reduce motion”.
struct Motion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: AnyHashable

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .smooth(duration: 0.3), value: value)
    }
}

extension View {
    func stateAnimation(_ value: some Hashable) -> some View { modifier(Motion(value: AnyHashable(value))) }
}
