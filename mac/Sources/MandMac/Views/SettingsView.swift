import MandMacKit
import SwiftUI

/// The standard macOS Settings window (M’AND → Settings…, ⌘,).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(QuickShareController.self) private var quickShare

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
                Toggle("Receive files from Android Quick Share", isOn: Binding(
                    get: { settings.quickShareEnabled },
                    set: { settings.quickShareEnabled = $0; quickShare.sync() }))
            } header: {
                Text("Quick Share (unofficial)")
            } footer: {
                Text("Lets any Android phone on this Wi-Fi send files with its built-in Share → Quick Share, without opening M’AND. While on, this Mac is visible to everyone on the network, and you approve each transfer. Uses an unofficial protocol (adapted from the open-source NearDrop) that Google can change at any time. Off by default.")
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
