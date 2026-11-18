import MandMacKit
import SwiftUI

struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        Group {
            if model.devices.isEmpty {
                ContentUnavailableView {
                    Label("No paired phones", systemImage: "iphone")
                } description: {
                    Text("Phones you pair appear here. You can remove them at any time.")
                } actions: {
                    Button("Pair a Phone") { model.startPairing() }.buttonStyle(.pill)
                }
            } else {
                List {
                    ForEach(model.devices) { device in
                        DeviceRow(device: device, isConnected: model.isConnected(device),
                                  onRename: {
                                      ui.renameDraft = device.name
                                      ui.deviceToRename = device
                                  },
                                  onForget: { ui.deviceToForget = device })
                    }
                }
            }
        }
        .alert("Rename phone", isPresented: Binding(get: { ui.deviceToRename != nil },
                                                    set: { if !$0 { ui.deviceToRename = nil } }),
               presenting: ui.deviceToRename) { device in
            @Bindable var ui = ui
            TextField("Name", text: $ui.renameDraft)
            Button("Rename") { model.renameDevice(device, to: ui.renameDraft) }
            Button("Use Phone’s Own Name") { model.renameDevice(device, to: "") }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This name is only used on this Mac.")
        }
        .confirmationDialog("Forget “\(ui.deviceToForget?.name ?? "")”?",
                            isPresented: Binding(get: { ui.deviceToForget != nil }, set: { if !$0 { ui.deviceToForget = nil } }),
                            presenting: ui.deviceToForget) { device in
            Button("Forget Phone", role: .destructive) { model.forget(device) }
        } message: { _ in
            Text("The phone will be disconnected and won’t be able to connect again until you pair it.")
        }
    }
}

private struct DeviceRow: View {
    let device: PairedDevice
    let isConnected: Bool
    let onRename: () -> Void
    let onForget: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            DeviceAvatar(connected: isConnected, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Text("Security code \(device.fingerprint.shortDisplay)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Rename…", action: onRename)
            Button("Forget…", action: onForget)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(device.name), \(detail)")
    }

    private var detail: String {
        if isConnected { return "Connected now" }
        guard let lastSeen = device.lastSeen else { return "Paired \(device.pairedAt.formatted(date: .abbreviated, time: .omitted)) · not seen since" }
        return "Last seen \(lastSeen.formatted(.relative(presentation: .named)))"
    }
}

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.log.isEmpty {
            ContentUnavailableView("No activity yet", systemImage: "list.bullet.rectangle",
                                   description: Text("Connections, pairing and errors are listed here. Message contents are never recorded."))
        } else {
            List(model.log.reversed()) { line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
                    Text(line.text).textSelection(.enabled)
                }
            }
        }
    }
}
