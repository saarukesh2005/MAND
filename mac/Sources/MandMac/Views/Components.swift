import SwiftUI

/// A quiet, native-feeling grouped container.
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
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title { Text(title).font(.headline) }
                    if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

struct FeatureTile: View {
    enum Status: Equatable {
        case available, needsPhone, comingSoon(String)
    }

    let symbol: String
    let title: String
    let status: Status

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(status == .available ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(status == .available ? 1 : 0.72)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch status {
        case .available: "Ready"
        case .needsPhone: "Connect your phone first"
        case .comingSoon(let milestone): "Not built yet · \(milestone)"
        }
    }
}

struct Tip: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}
