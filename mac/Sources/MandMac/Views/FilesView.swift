import AppKit
import MandCore
import MandMacKit
import SwiftUI

struct FilesView: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DropZone()
            QuickShareBanner()
            HStack {
                Label {
                    Text("Files from your phone are saved in ") + Text(model.settings.downloadFolder.lastPathComponent).bold()
                } icon: { Image(systemName: "folder") }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Show") { NSWorkspace.shared.open(Self.ensureFolder(model.settings.downloadFolder)) }
                    .buttonStyle(.link)
                Button("Change…") { model.chooseDownloadFolder() }
                    .buttonStyle(.link)
                Spacer()
                if model.transfers.contains(where: \.item.isFinished) {
                    Button("Clear History") { model.clearFinishedTransfers() }
                }
            }
            if model.transfers.isEmpty {
                ContentUnavailableView("No transfers yet", systemImage: "arrow.up.arrow.down",
                                       description: Text("Send files from this Mac, or share files to “M’AND” from your phone."))
            } else {
                List(model.transfers) { entry in TransferRow(item: entry.item, deviceName: entry.deviceName) }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
            }
        }
        .padding(24)
    }

    static func ensureFolder(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct DropZone: View {
    @Environment(AppModel.self) private var model
    @Environment(UIState.self) private var ui

    private var canSend: Bool { model.phoneSupports(Feature.files) }

    var body: some View {
        @Bindable var ui = ui
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.up.on.square")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(ui.isDropTargeted ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            Text(canSend ? "Drop files or folders here to send them to \(model.connected?.name ?? "your phone")"
                         : model.isConnected ? "Update M’AND on your phone to send files"
                                             : "Connect your phone to send files")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Choose Files…") { FilePicker.pick { model.sendFiles($0) } }
                .disabled(!canSend)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(ui.isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(ui.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.5)))
        .dropDestination(for: URL.self) { urls, _ in
            guard canSend else { return false }
            model.sendFiles(urls.filter(\.isFileURL))
            return true
        } isTargeted: { ui.isDropTargeted = $0 && canSend }
    }
}

private struct TransferRow: View {
    @Environment(AppModel.self) private var model
    let item: FileTransferService.Item
    let deviceName: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.direction == .incoming ? "arrow.down.circle" : "arrow.up.circle")
                .font(.title2)
                .foregroundStyle(tint)
                .accessibilityLabel(item.direction == .incoming ? "From phone" : "To phone")
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                if !item.isFinished, item.size > 0 {
                    ProgressView(value: Double(item.transferred), total: Double(item.size))
                        .progressViewStyle(.linear)
                }
                Text("\(detail) · \(item.direction == .incoming ? "from" : "to") \(deviceName)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var actions: some View {
        switch item.state {
        case .done, .alreadyThere:
            if item.direction == .incoming, let url = item.savedURL {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.link)
            }
        case .failed, .cancelled:
            if item.direction == .outgoing, model.liveTransfers.contains(where: { $0.id == item.id }) || model.isConnected {
                Button("Retry") { model.retryTransfer(item.id) }
            }
        default:
            Button("Cancel") { model.cancelTransfer(item.id) }
        }
    }

    private var tint: Color {
        switch item.state {
        case .done, .alreadyThere: Theme.positive
        case .failed: Theme.caution
        default: .accentColor
        }
    }

    private var detail: String {
        let size = ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
        switch item.state {
        case .preparing: return "Preparing · \(size)"
        case .waiting: return model.isConnected ? "Waiting · \(size)" : "Will send when your phone connects · \(size)"
        case .offered: return "Waiting for the phone… · \(size)"
        case .active:
            let done = ByteCountFormatter.string(fromByteCount: item.transferred, countStyle: .file)
            let speed = item.bytesPerSecond > 0
                ? " · " + ByteCountFormatter.string(fromByteCount: Int64(item.bytesPerSecond), countStyle: .file) + "/s" : ""
            return "\(done) of \(size)\(speed)"
        case .interrupted: return "Connection lost — will continue automatically"
        case .done: return item.direction == .incoming ? "Received · \(size)" : "Sent · \(size)"
        case .alreadyThere: return "Already there — not copied again"
        case .failed(let reason): return reason
        case .cancelled: return "Cancelled"
        }
    }
}
