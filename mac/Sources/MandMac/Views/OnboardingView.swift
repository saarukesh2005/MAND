import MandMacKit
import SwiftUI

/// First-launch welcome: what M’AND is, how it protects you, then pairing.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(UIState.self) private var ui

    private struct Page {
        let symbol: String
        let title: String
        let body: String
    }

    private let pages = [
        Page(symbol: "laptopcomputer.and.iphone", title: "Your phone. Your Mac. One ecosystem.",
             body: "Send files both ways, share copied text, see your phone’s notifications, battery and calls — right here on your Mac."),
        Page(symbol: "lock.shield", title: "Private by design",
             body: "M’AND talks to your phone directly over your own Wi-Fi, encrypted end to end. No cloud, no account, nothing leaves your network. Clipboard and notification sharing stay off until you turn them on."),
        Page(symbol: "qrcode.viewfinder", title: "Pair in a minute",
             body: "Install M’AND on your Android phone, then show a QR code here and scan it. Nothing is trusted until you click Allow on this Mac."),
    ]

    var body: some View {
        @Bindable var ui = ui
        let page = pages[ui.onboardingPage]
        VStack(spacing: Theme.Space.xl) {
            Image(systemName: page.symbol)
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Theme.accent)
                .frame(height: 70)
                .accessibilityHidden(true)
            VStack(spacing: Theme.Space.m) {
                Text(page.title).font(Theme.Font.hero).multilineTextAlignment(.center)
                Text(page.body).font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.Space.s) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle().fill(index == ui.onboardingPage ? Theme.accent : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(ui.onboardingPage + 1) of \(pages.count)")
            HStack {
                if ui.onboardingPage > 0 { Button("Back") { ui.onboardingPage -= 1 } }
                Spacer()
                Button("Skip") { finish(pair: false) }.buttonStyle(.link)
                if ui.onboardingPage < pages.count - 1 {
                    Button("Continue") { ui.onboardingPage += 1 }
                        .buttonStyle(.borderedProminent).tint(Theme.accent).keyboardShortcut(.defaultAction)
                } else {
                    Button("Pair My Phone") { finish(pair: true) }
                        .buttonStyle(.borderedProminent).tint(Theme.accent).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Theme.Space.xxl)
        .frame(width: 520)
        .stateAnimation(ui.onboardingPage)
    }

    private func finish(pair: Bool) {
        model.settings.hasCompletedOnboarding = true
        dismiss()
        if pair { model.startPairing() }
    }
}
