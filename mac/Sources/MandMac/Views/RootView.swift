import MandMacKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case devices = "Devices"
    case activity = "Activity"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house"
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
        .alert(
            "Allow “\(model.pendingApproval?.name ?? "this phone")” to pair with this Mac?",
            isPresented: Binding(get: { model.pendingApproval != nil },
                                 set: { if !$0 { model.respondToPairing(approved: false) } }),
            presenting: model.pendingApproval
        ) { _ in
            Button("Don’t Allow", role: .cancel) { model.respondToPairing(approved: false) }
            Button("Allow") { model.respondToPairing(approved: true) }
        } message: { request in
            Text("Only allow phones you own. Security code: \(request.fingerprint.shortDisplay)")
        }
    }
}
