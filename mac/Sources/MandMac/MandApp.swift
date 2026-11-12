import AppKit
import MandMacKit
import SwiftUI

@main
struct MandApp: App {
    // SwiftUI creates the App value once per launch, so these live for the whole session.
    // (Plain properties instead of @State: the @State macro needs Xcode's SwiftUIMacros plugin.)
    private let model = AppModel(macName: Host.current().localizedName ?? "Mac")
    private let ui = UIState()
    private let quickShare: QuickShareController

    init() {
        quickShare = QuickShareController(model: model)
    }

    var body: some Scene {
        Window("M’AND", id: "main") {
            RootView()
                .environment(model)
                .environment(ui)
                .environment(quickShare)
                .frame(minWidth: 760, minHeight: 520)
                .task {
                    model.start(identityProvider: { try DeviceIdentity.loadOrCreate(commonName: model.macName) })
                    quickShare.sync()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.stop()
                }
        }
        .defaultSize(width: 900, height: 620)

        Settings {
            SettingsView().environment(model).environment(quickShare)
        }

        MenuBarExtra {
            MenuBarContent().environment(model).environment(ui)
        } label: {
            Image(systemName: model.isConnected ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                .accessibilityLabel(model.isConnected ? "M’AND: phone connected" : "M’AND: no phone connected")
        }
    }
}

/// Compact status in the menu bar.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let phone = model.connected {
            Text("Connected to \(phone.name)")
        } else {
            Text("No phone connected")
        }
        Divider()
        Button("Open M’AND") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut("o")
        if let ringing = model.ringingPhone {
            Text("Incoming call: \(ringing.call?.caller ?? "Unknown caller")")
            Button("Answer on \(ringing.device.name)") { model.respondToCall(on: ringing, answer: true) }
            Button("Decline") { model.respondToCall(on: ringing, answer: false) }
            Divider()
        }
        if model.isConnected {
            if let status = model.phoneStatus {
                Text("Battery \(status.battery)%\(status.charging ? " · charging" : "")")
            }
            Button("Send Files…") {
                NSApp.activate()
                FilePicker.pick { model.sendFiles($0) }
            }
            Button("Send Clipboard to Phone") { model.sendClipboard() }
                .disabled(!model.settings.clipboardEnabled)
        }
        Button("Pair a Phone…") {
            ui.section = .home
            openWindow(id: "main")
            NSApp.activate()
            model.startPairing()
        }
        Divider()
        Button("Quit M’AND") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

/// View-only state shared by the window's screens.
@MainActor
@Observable
final class UIState {
    var section: AppSection = .home
    var draft = ""
    var deviceToForget: PairedDevice?
    var isDropTargeted = false
    var onboardingPage = 0
    var linkDraft = ""
    var isLinkSheetShown = false
    var deviceToRename: PairedDevice?
    var renameDraft = ""
}
