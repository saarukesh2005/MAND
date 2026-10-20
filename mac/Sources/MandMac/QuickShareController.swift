import AppKit
import MandMacKit
import MandQuickShare
import Observation

/// Glue between the optional Quick Share receiver and the app. Lives in the app target so the core
/// (MandMacKit) never depends on the unofficial protocol code.
@MainActor
@Observable
final class QuickShareController {
    enum Status: Equatable { case off, starting, visible, failed }

    private(set) var status: Status = .off
    private(set) var pending: [QuickShareRequest] = []
    private(set) var progress: [String: Double] = [:]
    private(set) var lastNotice: String?
    private(set) var lastLink: URL?

    private var receiver: QuickShareReceiver?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    /// Turns receiving on or off to match the setting.
    func sync() {
        model.settings.quickShareEnabled ? start() : stop()
    }

    func respond(to request: QuickShareRequest, accept: Bool) {
        pending.removeAll { $0.id == request.id }
        receiver?.respond(to: request.id, accept: accept)
        if accept { progress[request.id] = 0 }
    }

    func openLastLink() {
        if let lastLink { NSWorkspace.shared.open(lastLink) }
        lastLink = nil
    }

    func dismissNotice() {
        lastNotice = nil
        lastLink = nil
    }

    private func start() {
        guard receiver == nil else { return }
        status = .starting
        let partials = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("M’AND/QuickSharePartial", isDirectory: true)
        let receiver = QuickShareReceiver(deviceName: model.macName, destination: model.downloadFolderProvider,
                                          partialFolder: partials) { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(event) } }
        }
        self.receiver = receiver
        receiver.start()
    }

    private func stop() {
        receiver?.stop()
        receiver = nil
        pending = []
        progress = [:]
        status = .off
    }

    private func handle(_ event: QuickShareEvent) {
        switch event {
        case .advertising(let on):
            status = on ? .visible : (receiver == nil ? .off : .failed)
        case .requestNeedsConsent(let request):
            pending.append(request)
            NSApp.requestUserAttention(.informationalRequest)
        case .progress(let id, let received, let total):
            progress[id] = total > 0 ? Double(received) / Double(total) : 1
        case .finished(let id, let sender, let files, let link, let error):
            progress[id] = nil
            pending.removeAll { $0.id == id }
            if !files.isEmpty { model.recordReceived(files: files, from: sender) }
            if let link {
                lastLink = link
                lastNotice = "\(sender) shared a link: \(link.host() ?? link.absoluteString)"
            } else if let error {
                lastNotice = "Quick Share from \(sender): \(error)"
            } else if !files.isEmpty {
                lastNotice = "Received \(files.count) file\(files.count == 1 ? "" : "s") from \(sender) via Quick Share."
            }
        }
    }
}
