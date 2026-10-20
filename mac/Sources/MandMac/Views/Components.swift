import MandMacKit
import SwiftUI

/// A quiet raised surface with an optional header.
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
        .padding(Theme.Space.l + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

/// Small coloured dot that encodes connection state (always paired with text for accessibility).
struct StatusDot: View {
    let connected: Bool
    var body: some View {
        Circle().fill(connected ? Theme.positive : Color.secondary.opacity(0.5))
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

/// Phone glyph in a soft circle, with a ring when connected.
struct DeviceAvatar: View {
    let connected: Bool
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().fill((connected ? Theme.accent : Color.secondary).opacity(0.12))
            Circle().strokeBorder(connected ? Theme.accent : .clear, lineWidth: 2)
            Image(systemName: connected ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3")
                .font(.system(size: size * 0.42, weight: .regular))
                .foregroundStyle(connected ? Theme.accent : .secondary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Circular battery gauge. Shows "last known" styling when the reading is stale.
struct BatteryRing: View {
    let status: AppModel.PhoneStatus

    var body: some View {
        let stale = status.isStale()
        let fraction = Double(status.battery) / 100
        let tint: Color = stale ? .secondary : status.battery <= 15 && !status.charging ? Theme.critical : Theme.accent
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5)
            Circle().trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(status.battery)%").font(Theme.Font.numeral)
                if status.charging {
                    Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(tint)
                }
            }
        }
        .frame(width: 54, height: 54)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Phone battery \(status.battery) percent\(status.charging ? ", charging" : "")\(stale ? ", last known reading" : "")")
    }
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
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(status == .available ? Theme.accent : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.m)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
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
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}
