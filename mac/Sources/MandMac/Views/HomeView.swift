import MandMacKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatusCard()
                if model.isConnected {
                    TestMessageCard()
                } else if case .listening = model.serverStatus {
                    TroubleshootingCard()
                }
                FeaturesGrid()
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }
}

/// Answers “Is my phone connected?” at a glance.
struct StatusCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Circle().fill(tint.opacity(0.14)).frame(width: 64, height: 64)
                    Image(systemName: symbol).font(.system(size: 28, weight: .medium)).foregroundStyle(tint)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.weight(.semibold))
                    Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let notice = model.pairingNotice {
                        Text(notice).font(.callout).foregroundStyle(.secondary).padding(.top, 2)
                    }
                }
                Spacer(minLength: 12)
                if !model.isConnected, case .listening = model.serverStatus {
                    Button(model.devices.isEmpty ? "Pair a Phone" : "Pair Another Phone") { model.startPairing() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        if model.isConnected { return "iphone.radiowaves.left.and.right" }
        if case .failed = model.serverStatus { return "exclamationmark.triangle" }
        return "iphone"
    }

    private var tint: Color {
        if model.isConnected { return .green }
        if case .failed = model.serverStatus { return .orange }
        return .secondary
    }

    private var title: String {
        if let phone = model.connected { return "\(phone.name) is connected" }
        switch model.serverStatus {
        case .starting: return "Starting…"
        case .failed: return "M’AND can’t accept connections"
        case .listening: return model.devices.isEmpty ? "No phone paired yet" : "Phone not connected"
        }
    }

    private var subtitle: String {
        if model.isConnected {
            return "Secure, encrypted connection over your local network\(model.connectedAddress.map { " (\($0))" } ?? "")."
        }
        switch model.serverStatus {
        case .starting: return "Getting ready to connect."
        case .failed(let reason): return "\(reason). Try quitting and reopening M’AND."
        case .listening:
            if model.devices.isEmpty { return "Pair your Android phone to get started. It takes about a minute." }
            if let last = model.lastDisconnect {
                return "\(last.name) disconnected \(last.date.formatted(.relative(presentation: .named))): \(last.reason)."
            }
            let names = model.devices.map(\.name).joined(separator: ", ")
            return "Waiting for \(names). Open M’AND on the phone and make sure it’s on the same Wi-Fi."
        }
    }
}

struct TestMessageCard: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        @Bindable var ui = ui
        Card(title: "Test message", subtitle: "Check the connection by sending a short note to your phone.") {
            VStack(alignment: .leading, spacing: 10) {
                if !model.chat.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.chat.suffix(6)) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: line.direction == .fromMac ? "laptopcomputer" : "iphone")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(line.direction == .fromMac ? "From this Mac" : "From phone")
                                Text(line.text).textSelection(.enabled)
                                Spacer()
                                Text(line.date, style: .time).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                HStack {
                    TextField("Type a message", text: $ui.draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(send)
                    Button("Send", action: send)
                        .disabled(ui.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func send() {
        if model.sendTestMessage(ui.draft) { ui.draft = "" }
    }
}

/// “How do I fix a connection problem?”
struct TroubleshootingCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(title: "Can’t connect?", subtitle: nil) {
            VStack(alignment: .leading, spacing: 8) {
                Tip("Both devices must be on the same Wi-Fi network (not a guest network).")
                Tip("If macOS asked about Local Network access for M’AND, choose Allow. You can change it in System Settings → Privacy & Security → Local Network.")
                Tip("On the phone, keep M’AND allowed to run in the background (Settings → Apps → M’AND → Battery → Unrestricted).")
                Tip("Some routers block devices from seeing each other (“client isolation”). Try a home network or phone hotspot.")
                if !model.isAdvertising {
                    Tip("This Mac isn’t visible on the network yet, so the phone will use the last address it knew.")
                }
            }
        }
    }
}

struct FeaturesGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What you can do").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                FeatureTile(symbol: "text.bubble", title: "Test message",
                            status: model.isConnected ? .available : .needsPhone)
                FeatureTile(symbol: "doc.on.doc", title: "Send files", status: .comingSoon("Milestone 2"))
                FeatureTile(symbol: "doc.on.clipboard", title: "Clipboard sharing", status: .comingSoon("Milestone 3"))
                FeatureTile(symbol: "bell.badge", title: "Phone notifications", status: .comingSoon("Milestone 4"))
                FeatureTile(symbol: "battery.75percent", title: "Battery level", status: .comingSoon("Milestone 4"))
                FeatureTile(symbol: "rectangle.on.rectangle", title: "Screen mirroring", status: .comingSoon("Milestone 5"))
            }
        }
    }
}
