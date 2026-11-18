import AppKit
import MandMacKit
import SwiftUI

/// A big rounded card lit from the top, with an optional header.
struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title { Text(title).font(Theme.Font.section).accessibilityAddTraits(.isHeader) }
                    if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(Theme.Space.l + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
            .strokeBorder(Theme.bevel.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }
}

/// The dark hero card from the design: always black-to-graphite, white text.
struct HeroCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.hero, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                              lineWidth: 1))
            .shadow(color: .black.opacity(0.30), radius: 24, y: 12)
            .environment(\.colorScheme, .dark)
    }
}

/// Connection dot. Pulses gently while connected; always paired with words for accessibility.
struct StatusDot: View {
    let connected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if connected && !reduceMotion {
                Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                    .frame(width: 8, height: 8)
                    .phaseAnimator([false, true]) { ring, expanded in
                        ring.scaleEffect(expanded ? 2.6 : 1).opacity(expanded ? 0 : 0.9)
                    } animation: { _ in .easeOut(duration: 1.4) }
            }
            Circle().fill(connected ? Color.white : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
                .shadow(color: connected ? .white.opacity(0.9) : .clear, radius: 4)
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// A round chrome button/icon like the design's bottom bar.
struct ChromeOrb: View {
    let symbol: String
    var size: CGFloat = 44
    var dark = true

    var body: some View {
        ZStack {
            Circle().fill(dark
                ? LinearGradient(colors: [Color(white: 0.34), Color(white: 0.10)], startPoint: .top, endPoint: .bottom)
                : LinearGradient(colors: [.white, Color(white: 0.80)], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.45 : 0.9), .white.opacity(0.0)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(dark ? ChromeStyle.shine : ChromeStyle.graphite)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(dark ? 0.35 : 0.15), radius: 6, y: 3)
    }
}

/// The phone as a big chrome orb, ringed when connected.
struct DeviceAvatar: View {
    let connected: Bool
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().strokeBorder(connected ? Color.white.opacity(0.9) : Color.white.opacity(0.15), lineWidth: 2)
                .padding(-5)
            ChromeOrb(symbol: connected ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3", size: size)
        }
        .frame(width: size + 10, height: size + 10)
        .accessibilityHidden(true)
    }
}

/// Circular battery gauge; the ring sweeps to the new level. "Last known" styling when stale.
struct BatteryRing: View {
    let status: AppModel.PhoneStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stale = status.isStale()
        let fraction = Double(status.battery) / 100
        let low = status.battery <= 15 && !status.charging
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
            Circle().trim(from: 0, to: fraction)
                .stroke(low ? AnyShapeStyle(Theme.critical) : AnyShapeStyle(ChromeStyle.shine),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(stale ? 0.4 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.85), value: status.battery)
            VStack(spacing: 0) {
                Text("\(status.battery)%").font(Theme.Font.numeral).contentTransition(.numericText())
                if status.charging {
                    Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(ChromeStyle.shine)
                }
            }
        }
        .frame(width: 60, height: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Phone battery \(status.battery) percent\(status.charging ? ", charging" : "")\(stale ? ", last known reading" : "")")
    }
}

/// Lift-on-hover behaviour shared by tiles. (`State` is used directly; the `@State` shorthand needs Xcode.)
struct HoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let hovering = State(initialValue: false)

    func body(content: Content) -> some View {
        let isHovering = hovering.wrappedValue
        return content
            .scaleEffect(isHovering && !reduceMotion ? 1.025 : 1)
            .shadow(color: .black.opacity(isHovering ? 0.18 : 0.06), radius: isHovering ? 16 : 6, y: isHovering ? 8 : 3)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
            .onHover { hovering.wrappedValue = $0 }
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
}

struct FeatureTile: View {
    enum Status: Equatable {
        case available, needsPhone, phoneUpdate, off
        case ready(String), setup(String)
    }

    let symbol: String
    let title: String
    let status: Status

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ChromeOrb(symbol: symbol, size: 36, dark: status == .available)
                .opacity(status == .available ? 1 : 0.7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, design: .rounded).weight(.semibold))
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(Theme.Space.m)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.bevel.opacity(0.5)))
        .hoverLift()
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch status {
        case .available: "Ready"
        case .needsPhone: "Connect your phone first"
        case .phoneUpdate: "Update M’AND on the phone"
        case .off: "Off · turn on in Settings"
        case .ready(let note): note
        case .setup(let note): note
        }
    }
}

struct Tip: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: "sparkle").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}

/// A large, clearly labelled action: chrome orb, title and one line saying what it does (or why it can't yet).
struct ActionTile: View {
    let symbol: String
    let title: String
    let hint: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                ChromeOrb(symbol: symbol, size: 40, dark: isEnabled)
                    .accessibilityHidden(true)
                Text(title).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(.primary)
                Text(hint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(Theme.Space.m + 2)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.bevel.opacity(0.6)))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(SquishStyle())
        .hoverLift()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .help(hint)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

/// Presses squish slightly, so every tap feels answered.
struct SquishStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A one-line status message with an icon, announced to VoiceOver when it changes.
struct NoticeLine: View {
    let text: String
    var symbol = "info.circle"

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear { announce() }
            .onChange(of: text) { announce() }
    }

    private func announce() {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

/// A feature that starts off, with its switch right on the tile (no trip to Settings needed).
struct FeatureToggleTile: View {
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: Theme.Space.m) {
                ChromeOrb(symbol: symbol, size: 36, dark: isOn)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.body, design: .rounded).weight(.semibold))
                    Text(isOn ? "On · \(detail)" : "Off · \(detail)").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(Theme.bevel.opacity(0.5)))
        .hoverLift()
        .accessibilityHint(detail)
    }
}

/// The design's floating bar: a dark capsule of round chrome buttons for the most common actions.
struct FloatingDock: View {
    struct Item: Identifiable {
        let symbol: String
        let label: String
        var isEnabled = true
        let action: () -> Void
        var id: String { label }
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ForEach(items) { item in
                Button(action: item.action) { ChromeOrb(symbol: item.symbol, size: 46) }
                    .buttonStyle(SquishStyle())
                    .disabled(!item.isEnabled)
                    .opacity(item.isEnabled ? 1 : 0.4)
                    .help(item.label)
                    .accessibilityLabel(item.label)
            }
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s + 2)
        .background(Capsule().fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.02)], startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom)))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }
}
