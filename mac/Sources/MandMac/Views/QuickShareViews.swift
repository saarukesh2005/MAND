import MandMacKit
import MandQuickShare
import SwiftUI

/// Accept/Decline sheet for an incoming Quick Share transfer.
struct QuickShareConsentSheet: View {
    @Environment(QuickShareController.self) private var quickShare
    let request: QuickShareRequest

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "dot.radiowaves.left.and.right").font(.title).foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(request.senderName) wants to share").font(Theme.Font.title)
                    Text("via Quick Share · unofficial").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let title = request.linkTitle {
                Label("A link: \(title)", systemImage: "link")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(request.fileNames.prefix(8), id: \.self) { Label($0, systemImage: "doc") }
                    if request.fileNames.count > 8 { Text("and \(request.fileNames.count - 8) more…").foregroundStyle(.secondary) }
                    Text(ByteCountFormatter.string(fromByteCount: request.totalBytes, countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let pin = request.pinCode {
                Text("Check the phone shows PIN \(pin)").font(.callout.monospacedDigit())
                    .padding(Theme.Space.s)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            }
            HStack {
                Spacer()
                Button("Decline", role: .cancel) { quickShare.respond(to: request, accept: false) }
                    .keyboardShortcut(.cancelAction)
                Button("Accept") { quickShare.respond(to: request, accept: true) }
                    .buttonStyle(.pill).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 420)
    }
}

/// Banner on the Files screen while Quick Share is on (progress, last result, link to open).
struct QuickShareBanner: View {
    @Environment(QuickShareController.self) private var quickShare

    var body: some View {
        if quickShare.status != .off || quickShare.lastNotice != nil {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Theme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.medium))
                    if let notice = quickShare.lastNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(quickShare.progress.values), id: \.self) { ProgressView(value: $0).frame(maxWidth: 240) }
                }
                Spacer()
                if quickShare.lastLink != nil { Button("Open Link") { quickShare.openLastLink() } }
                if quickShare.lastNotice != nil { Button("Dismiss") { quickShare.dismissNotice() }.buttonStyle(.link) }
            }
            .padding(Theme.Space.m)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
    }

    private var title: String {
        switch quickShare.status {
        case .off: "Quick Share is off"
        case .starting: "Starting Quick Share…"
        case .visible: "Visible to Quick Share on this Wi-Fi as “\(Host.current().localizedName ?? "this Mac")”"
        case .failed: "Quick Share couldn’t start. Check Local Network access for M’AND."
        }
    }
}
