import AppKit
import MandCore
import MandMacKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl - 4) {
                if let ringing = model.ringingPhone { CallBanner(phone: ringing) }
                if let finding = model.phones.first(where: \.isRinging) { FindBanner(phone: finding) }
                if model.phones.count > 1 { DeviceSwitcher() }
                PhoneHero()
                if model.isConnected {
                    Card { QuickActions() }
                    TestMessageCard()
                } else if case .listening = model.serverStatus, !model.devices.isEmpty {
                    TroubleshootingCard()
                }
                FeaturesGrid()
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 860, alignment: .leading)
            .stateAnimation(model.phones.map(\.id))
        }
    }
}

/// The glanceable answer to “Is my phone connected, and what can I do?”
struct PhoneHero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: Theme.Space.l + 2) {
                DeviceAvatar(connected: model.isConnected, size: 64)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack(spacing: Theme.Space.s) {
                        StatusDot(connected: model.isConnected)
                        Text(statusWord).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    Text(title).font(Theme.Font.hero).lineLimit(2)
                    Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let details = phoneDetails {
                        Text(details).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let notice = model.pairingNotice {
                        Text(notice).font(.callout).foregroundStyle(.secondary).padding(.top, 2)
                    }
                }
                Spacer(minLength: Theme.Space.m)
                if let status = model.phoneStatus { BatteryRing(status: status) }
                if !model.isConnected, case .listening = model.serverStatus {
                    Button(model.devices.isEmpty ? "Pair a Phone" : "Pair Another") { model.startPairing() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .controlSize(.large)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// "Pixel 7a · Android 16 · 52 GB free of 128 GB · Connection: Excellent"
    private var phoneDetails: String? {
        guard let phone = model.selected else { return nil }
        var parts: [String] = []
        if let info = phone.info {
            parts.append(info.model)
            parts.append(info.os)
            parts.append(Friendly.storage(free: info.storageFree, total: info.storageTotal))
        }
        if let ms = phone.latencyMs { parts.append("Connection: \(Friendly.quality(latencyMs: ms).rawValue)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var statusWord: String {
        if model.isConnected { return "Connected" }
        switch model.serverStatus {
        case .starting: return "Starting"
        case .failed: return "Needs attention"
        case .listening: return model.devices.isEmpty ? "Not paired" : "Waiting"
        }
    }

    private var title: String {
        if let phone = model.connected { return phone.name }
        switch model.serverStatus {
        case .starting: return "Getting ready…"
        case .failed: return "M’AND can’t accept connections"
        case .listening: return model.devices.isEmpty ? "Pair your Android phone" : "Phone not connected"
        }
    }

    private var subtitle: String {
        if model.isConnected {
            var parts = ["Encrypted · local network"]
            if let address = model.connectedAddress { parts.append(address) }
            if let status = model.phoneStatus, status.isStale() {
                parts.append("battery updated \(status.updated.formatted(.relative(presentation: .named)))")
            }
            if model.phones.count > 1 { parts.append("\(model.phones.count) phones connected") }
            return parts.joined(separator: " · ")
        }
        switch model.serverStatus {
        case .starting: return "Starting the secure connection service."
        case .failed(let reason): return "\(reason). Quit and reopen M’AND to try again."
        case .listening:
            if model.devices.isEmpty { return "Scan a QR code with M’AND on your phone. It takes about a minute." }
            if let last = model.lastDisconnect {
                return "\(last.name) disconnected \(last.date.formatted(.relative(presentation: .named))): \(last.reason)."
            }
            return "Open M’AND on your phone and make sure both are on the same Wi-Fi."
        }
    }
}

/// Chips to choose which connected phone actions go to.
struct DeviceSwitcher: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text("Send to").font(.callout).foregroundStyle(.secondary)
            ForEach(model.phones) { phone in
                let isSelected = model.selected?.id == phone.id
                Button {
                    model.select(phone)
                } label: {
                    Label(phone.device.name, systemImage: "iphone.gen3")
                        .padding(.horizontal, Theme.Space.m).padding(.vertical, 6)
                        .background(isSelected ? Theme.accent.opacity(0.16) : Theme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(isSelected ? Theme.accent : Theme.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// Prominent banner for a ringing phone. Answer/decline happen on the phone; audio stays there.
struct CallBanner: View {
    @Environment(AppModel.self) private var model
    let phone: AppModel.ConnectedPhone

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            Image(systemName: "phone.arrow.down.left.fill")
                .font(.title2).foregroundStyle(Theme.accent)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(phone.call?.caller ?? "Incoming call").font(Theme.Font.title)
                Text("Ringing on \(phone.device.name) · the call audio stays on your phone")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) { model.respondToCall(on: phone, answer: false) } label: {
                Label("Decline", systemImage: "phone.down.fill")
            }
            .controlSize(.large)
            Button { model.respondToCall(on: phone, answer: true) } label: {
                Label("Answer", systemImage: "phone.fill")
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.large)
        }
        .padding(Theme.Space.l)
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Incoming call from \(phone.call?.caller ?? "unknown caller") on \(phone.device.name)")
    }
}

/// The things people do most, as big labelled tiles. A disabled tile says why and what to do.
struct QuickActions: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        @Bindable var ui = ui
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("What would you like to do?").font(Theme.Font.section).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                ActionTile(symbol: "square.and.arrow.up", title: "Send Files",
                           hint: model.phoneSupports(Feature.files) ? "Pick files or folders, or drag them onto this window"
                                                                     : "Update M’AND on your phone first",
                           isEnabled: model.phoneSupports(Feature.files)) { FilePicker.pick { model.sendFiles($0) } }
                ActionTile(symbol: "doc.on.clipboard", title: "Send Clipboard",
                           hint: model.settings.clipboardEnabled ? "Copy something on the Mac, then press this"
                                                                 : "Turn on Clipboard below first",
                           isEnabled: model.settings.clipboardEnabled && model.phoneSupports(Feature.clipboard)) {
                    model.sendClipboard()
                }
                ActionTile(symbol: "link", title: "Open Link on Phone",
                           hint: model.phoneSupports(Feature.link) ? "Send a web page to your phone"
                                                                   : "Update M’AND on your phone first",
                           isEnabled: model.phoneSupports(Feature.link)) {
                    ui.linkDraft = model.clipboardLink ?? ""
                    ui.isLinkSheetShown = true
                }
                ActionTile(symbol: "speaker.wave.3", title: "Find My Phone",
                           hint: model.phoneSupports(Feature.find) ? "Make it ring loudly, even on silent"
                                                                   : "Update M’AND on your phone first",
                           isEnabled: model.phoneSupports(Feature.find)) { model.ringPhone() }
                ActionTile(symbol: "rectangle.on.rectangle", title: "Mirror Screen",
                           hint: "See your phone’s screen on the Mac (USB cable)") { ui.section = .mirroring }
            }
            ForEach(notices, id: \.self) { NoticeLine(text: $0) }
        }
        .sheet(isPresented: $ui.isLinkSheetShown) { SendLinkSheet() }
    }

    private var notices: [String] {
        [model.clipboardNotice, model.linkNotice, model.settings.tapEnabled ? model.tapNotice : nil].compactMap { $0 }
    }
}

/// Asks for one web link and sends it to the phone, which shows "Open link from your Mac".
struct SendLinkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var ui = ui
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Open a link on your phone").font(Theme.Font.title).accessibilityAddTraits(.isHeader)
            Text("Paste a web address. Your phone shows a notification; tap it to open the page.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("https://…", text: $ui.linkDraft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Web address")
                .onSubmit(send)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Send to Phone", action: send)
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(ui.linkDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 440)
    }

    private func send() {
        if model.sendLink(ui.linkDraft) == .sent { dismiss() }
    }
}

/// Shown while the phone plays the find-my-phone sound.
struct FindBanner: View {
    @Environment(AppModel.self) private var model
    let phone: AppModel.ConnectedPhone

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            Image(systemName: "speaker.wave.3.fill").font(.title2).foregroundStyle(Theme.accent)
                .symbolEffect(.variableColor.iterative).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(phone.device.name) is ringing").font(Theme.Font.title)
                Text("Follow the sound. It stops when you touch the phone or press Stop.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.stopRingingPhone() } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.large)
        }
        .padding(Theme.Space.l)
        .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

struct TestMessageCard: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        @Bindable var ui = ui
        Card(title: "Messages", subtitle: "Send a quick note to \(model.connected?.name ?? "your phone").") {
            VStack(alignment: .leading, spacing: Theme.Space.s + 2) {
                ForEach(model.chat.suffix(6)) { line in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Image(systemName: line.direction == .fromMac ? "laptopcomputer" : "iphone.gen3")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(line.direction == .fromMac ? "From this Mac" : "From \(line.deviceName)")
                        Text(line.text).textSelection(.enabled)
                        Spacer()
                        Text(line.date, style: .time).font(.caption).foregroundStyle(.tertiary)
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
        Card(title: "Can’t connect?") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Tip("Both devices must be on the same Wi-Fi network (not a guest network).")
                Tip("If macOS asked about Local Network access for M’AND, choose Allow (System Settings → Privacy & Security → Local Network).")
                Tip("On the phone, keep M’AND unrestricted in the background (Settings → Apps → M’AND → Battery).")
                Tip("Some routers block devices from seeing each other (“client isolation”). Try a home network or a phone hotspot.")
                if case .listening(let port) = model.serverStatus {
                    let addresses = LocalAddresses.privateIPv4()
                    Text(addresses.isEmpty
                         ? "This Mac isn’t on a local network right now."
                         : "This Mac’s address: \(addresses.joined(separator: " or ")) (port \(port)). Enter it on the phone if it can’t find the Mac.")
                        .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        .padding(.top, Theme.Space.xs)
                }
            }
        }
    }
}

/// Every feature with its state in plain words. Features that start off can be switched on right here.
struct FeaturesGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Everything M’AND can do").font(Theme.Font.section).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                FeatureTile(symbol: "doc.on.doc", title: "Files", status: status(Feature.files))
                FeatureToggleTile(symbol: "doc.on.clipboard", title: "Clipboard",
                                  detail: "Share copied text with your phone. Passwords are never sent.",
                                  isOn: Binding(get: { model.settings.clipboardEnabled }, set: { model.setClipboardEnabled($0) }))
                FeatureTile(symbol: "bell.badge", title: "Notifications", status: status(Feature.notifications))
                FeatureTile(symbol: "phone", title: "Calls", status: status(Feature.calls))
                FeatureTile(symbol: "battery.75percent", title: "Battery and phone details", status: status(Feature.device))
                FeatureTile(symbol: "speaker.wave.3", title: "Find My Phone", status: status(Feature.find))
                FeatureTile(symbol: "link", title: "Links", status: status(Feature.link))
                FeatureTile(symbol: "rectangle.on.rectangle", title: "Screen mirroring", status: mirroringStatus)
                FeatureToggleTile(symbol: "hand.tap", title: "Tap to Send",
                                  detail: "Hold the phone against the notch to send its screen. Experimental.",
                                  isOn: Binding(get: { model.settings.tapEnabled }, set: { model.setTapEnabled($0) }))
            }
        }
    }

    private func status(_ feature: String) -> FeatureTile.Status {
        guard model.isConnected else { return .needsPhone }
        return model.phoneSupports(feature) ? .available : .phoneUpdate
    }

    private var mirroringStatus: FeatureTile.Status {
        switch model.mirroringState {
        case .notInstalled: .setup("Needs scrcpy (free)")
        case .running: .available
        default: .ready("Uses a USB cable")
        }
    }
}

/// Opens a standard file picker that allows multiple files and folders.
enum FilePicker {
    @MainActor
    static func pick(_ completion: ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Send"
        panel.message = "Choose files or folders to send to your phone."
        if panel.runModal() == .OK { completion(panel.urls) }
    }
}
