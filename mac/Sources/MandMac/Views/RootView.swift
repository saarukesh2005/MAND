import MandMacKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case files = "Files"
    case notifications = "Notifications"
    case mirroring = "Screen Mirroring"
    case devices = "Devices"
    case activity = "Activity"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house"
        case .files: "doc.on.doc"
        case .notifications: "bell.badge"
        case .mirroring: "rectangle.on.rectangle"
        case .devices: "iphone"
        case .activity: "list.bullet.rectangle"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        @Bindable var ui = ui
        NavigationSplitView {
            List(AppSection.allCases, selection: Binding($ui.section)) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            Group {
                if let error = model.startupError {
                    ContentUnavailableView("M’AND couldn’t start", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else {
                    switch ui.section {
                    case .home: HomeView()
                    case .files: FilesView()
                    case .notifications: NotificationsView()
                    case .mirroring: MirroringView()
                    case .devices: DevicesView()
                    case .activity: ActivityView()
                    }
                }
            }
            .navigationTitle(ui.section.rawValue)
        }
        .sheet(isPresented: Binding(get: { model.invitation != nil }, set: { if !$0 { model.cancelPairing() } })) {
            PairingSheet()
        }
        .sheet(isPresented: Binding(
            get: { !model.settings.hasCompletedOnboarding && model.devices.isEmpty && model.startupError == nil
                   && model.invitation == nil },
            set: { if !$0 { model.settings.hasCompletedOnboarding = true } })) {
            OnboardingView()
        }
        .alert(
            "Allow “\(model.pendingApproval?.name ?? "this phone")” to pair with this Mac?",
            isPresented: Binding(get: { model.pendingApproval != nil },
                                 set: { if !$0 { model.respondToPairing(approved: false) } }),
            presenting: model.pendingApproval
        ) { _ in
            Button("Don’t Allow", role: .cancel) { model.respondToPairing(approved: false) }
            Button("Allow") { model.respondToPairing(approved: true) }
        } message: { request in
            Text("Only allow phones you own. Check that your phone shows this security code: \(request.fingerprint.shortDisplay)")
        }
    }
}
