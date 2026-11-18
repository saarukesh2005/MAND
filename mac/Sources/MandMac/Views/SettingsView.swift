import MandMacKit
import SwiftUI

/// The standard macOS Settings window (M’AND → Settings…, ⌘,).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(QuickShareController.self) private var quickShare

    /// Where Tap to Send stands, in one sentence.
    private var tapStatus: String {
        if model.tapSensorAvailable == false { return "This Mac has no notch light sensor (it needs a MacBook with a notch, lid open)." }
        let phoneReady = model.phones.contains(where: \.tapReady)
        switch (model.settings.tapEnabled, phoneReady) {
        case (true, true): return "Ready. Hold your phone on the notch."
        case (true, false): return "Ready on this Mac. Now turn it on in M’AND on your phone."
        case (false, true): return "Your phone is ready. Switch this on."
        case (false, false): return "Turn it on in M’AND on your phone; this Mac then switches on too."
        }
    }

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("General") {
                Toggle("Open M’AND when I log in", isOn: Binding(get: { model.launchAtLogin },
                                                                 set: { model.setLaunchAtLogin($0) }))
            }
            Section {
                Toggle("Share clipboard text with my phone", isOn: Binding(get: { settings.clipboardEnabled },
                                                                           set: { model.setClipboardEnabled($0) }))
                Toggle("Send text automatically when I copy on this Mac",
                       isOn: Binding(get: { settings.clipboardAutoSend }, set: { model.setClipboardAutoSend($0) }))
                    .disabled(!settings.clipboardEnabled)
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Off by default. Passwords and items your password manager marks as private are never sent. No clipboard history is kept.")
            }
            Section {
                Toggle("Also show phone notifications in macOS Notification Center",
                       isOn: Binding(get: { settings.notificationsInMacCenter },
                                     set: { model.setNotificationsInMacCenter($0) }))
            } header: {
                Text("Notifications")
            } footer: {
                Text("You choose which phone apps share notifications in M’AND on your phone.")
            }
            Section {
                Toggle("Open links from my phone straight away", isOn: $settings.openLinksFromPhone)
            } header: {
                Text("Links")
            } footer: {
                Text("When you share a web page to M’AND on your phone, it opens in your Mac’s browser. Turn this off to put the link on the clipboard instead. Only web links (http and https) are ever opened.")
            }
            Section {
                Toggle("Receive files from Android Quick Share", isOn: Binding(
                    get: { settings.quickShareEnabled },
                    set: { settings.quickShareEnabled = $0; quickShare.sync() }))
            } header: {
                Text("Quick Share (unofficial)")
            } footer: {
                Text("Lets any Android phone on this Wi-Fi send files with its built-in Share → Quick Share, without opening M’AND. While on, this Mac is visible to everyone on the network, and you approve each transfer. Uses an unofficial protocol (adapted from the open-source NearDrop) that Google can change at any time. Off by default.")
            }
            Section {
                Toggle("Tap to Send", isOn: Binding(get: { settings.tapEnabled }, set: { model.setTapEnabled($0) }))
                Text(tapStatus).foregroundStyle(.secondary)
                if let notice = model.tapNotice { Text(notice).foregroundStyle(.secondary) }
            } header: {
                Text("Tap to Send")
            } footer: {
                Text("Hold the top of your phone’s screen against the black notch at the top of this screen until the phone buzzes. Whatever is on the phone appears here. Turns on by itself when you switch it on in the phone app. Uses an undocumented macOS sensor interface (from the open-source TapDrop), so a macOS update could affect it.")
            }
            Section("Files") {
                LabeledContent("Save files from phone in") {
                    HStack {
                        Text(settings.downloadFolder.path).lineLimit(1).truncationMode(.middle)
                        Button("Change…") { model.chooseDownloadFolder() }
                    }
                }
            }
            if let notice = model.settingsNotice {
                Text(notice).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
    }
}
