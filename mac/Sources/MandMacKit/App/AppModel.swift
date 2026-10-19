import AppKit
import Foundation
import MandCore
import Observation

/// Everything the Mac UI shows, derived only from real server events.
@MainActor
@Observable
public final class AppModel {
    public enum ServerStatus: Equatable {
        case starting
        case listening(port: UInt16)
        case failed(String)
    }

    public struct ChatLine: Identifiable, Equatable {
        public enum Direction { case fromPhone, fromMac }
        public let id = UUID()
        public let direction: Direction
        public let text: String
        public let date: Date
    }

    public struct LogLine: Identifiable, Equatable {
        public let id = UUID()
        public let date: Date
        public let text: String
    }

    public struct PhoneStatus: Equatable {
        public let battery: Int
        public let charging: Bool
        public let updated: Date
    }

    public static let maxLogLines = 200
    public static let maxChatLines = 100
    public static let maxNotifications = 200

    // Connection
    public private(set) var serverStatus: ServerStatus = .starting
    public private(set) var isAdvertising = false
    public private(set) var devices: [PairedDevice] = []
    public private(set) var connected: PairedDevice?
    public private(set) var connectedAddress: String?
    public private(set) var phoneFeatures: Set<String> = []
    public private(set) var lastDisconnect: (name: String, reason: String, date: Date)?
    public private(set) var invitation: PairingInvitation?
    public private(set) var pairingNotice: String?
    public private(set) var chat: [ChatLine] = []
    public private(set) var log: [LogLine] = []
    public private(set) var startupError: String?
    public var pendingApproval: BridgeServer.PairingRequest?

    // Features
    public private(set) var transfers: [FileTransferService.Item] = []
    public private(set) var phoneStatus: PhoneStatus?
    public private(set) var notifications: [PhoneNotification] = []
    public private(set) var clipboardNotice: String?
    public private(set) var mirroringState: ScrcpyManager.State = .notInstalled
    public private(set) var mirroringOutput: [String] = []
    public private(set) var settingsNotice: String?
    public let settings: AppSettings

    public let macName: String
    private var server: BridgeServer?
    private var files: FileTransferService?
    private let clipboard = ClipboardService()
    private let notifier = MacNotifier()
    private let scrcpy: ScrcpyManager
    private let downloadFolderBox = LockedValue(AppSettings.defaultDownloadFolder)

    public init(macName: String, settings: AppSettings = AppSettings()) {
        self.macName = macName
        self.settings = settings
        scrcpy = ScrcpyManager(customPath: settings.scrcpyPath)
        scrcpy.onChange = { [weak self] in self?.syncMirroring() }
        syncMirroring()
    }

    public var isConnected: Bool { connected != nil }
    public var macFingerprint: Fingerprint? { server?.identity.fingerprint }

    public func phoneSupports(_ feature: String) -> Bool { isConnected && phoneFeatures.contains(feature) }

    // MARK: - Lifecycle

    /// Loads (or creates) this Mac's identity and starts listening.
    public func start(identityProvider: () throws -> DeviceIdentity,
                      store: PairedDeviceStore = KeychainPairedDeviceStore()) {
        guard server == nil else { return }
        let identity: DeviceIdentity
        do {
            identity = try identityProvider()
        } catch {
            startupError = "M’AND couldn’t set up its security key: \(error)"
            return
        }

        let box = ServerReference()
        let folder = downloadFolderBox
        folder.set(settings.downloadFolder)
        let files = FileTransferService(
            destination: { folder.get() },
            send: { message, completion in
                guard let server = box.server else { completion?(false); return }
                server.send(message, completion: completion)
            },
            onChange: { [weak self] items in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.transfers = items } }
            })
        let server = BridgeServer(identity: identity, store: store, deviceName: macName) { [weak self] event in
            // File chunks go straight to the transfer queue; everything else to the UI, in order.
            if case .featureMessage(let message) = event, message.feature == Feature.files {
                files.handle(message)
                return
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(event) } }
        }
        box.server = server
        self.files = files
        self.server = server
        files.cleanUpPartials()
        server.start()
        if settings.clipboardAutoSend { startClipboardWatch() }
        if settings.notificationsInMacCenter { Task { _ = await notifier.requestAuthorization() } }
    }

    public func stop() {
        server?.stop()
        scrcpy.stop()
    }

    // MARK: - Pairing and devices

    public func startPairing() {
        pairingNotice = nil
        server?.openPairingWindow()
    }

    public func cancelPairing() {
        server?.closePairingWindow()
        invitation = nil
    }

    public func respondToPairing(approved: Bool) {
        guard let request = pendingApproval else { return }
        pendingApproval = nil
        server?.resolvePairing(id: request.id, approved: approved)
    }

    /// Returns false (and sends nothing) if the text is empty, too long, or no phone is connected.
    @discardableResult
    public func sendTestMessage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConnected, !trimmed.isEmpty, trimmed.utf8.count <= Message.maxTextBytes else { return false }
        server?.sendText(trimmed)
        appendChat(ChatLine(direction: .fromMac, text: trimmed, date: Date()))
        return true
    }

    public func forget(_ device: PairedDevice) {
        server?.forget(device.fingerprint)
    }

    // MARK: - Files

    public func sendFiles(_ urls: [URL]) {
        files?.send(urls: urls)
    }

    public func cancelTransfer(_ id: String) { files?.cancel(id: id) }
    public func retryTransfer(_ id: String) { files?.retry(id: id) }
    public func clearFinishedTransfers() { files?.clearFinished() }

    public func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose where files from your phone are saved."
        panel.directoryURL = settings.downloadFolder
        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadFolder = url
            downloadFolderBox.set(url)
        }
    }

    // MARK: - Clipboard

    /// Sends the Mac clipboard to the phone (deliberate user action).
    public func sendClipboard() {
        guard settings.clipboardEnabled else {
            clipboardNotice = "Turn on clipboard sharing first."
            return
        }
        guard phoneSupports(Feature.clipboard) else {
            clipboardNotice = "Connect a phone with clipboard sharing to send."
            return
        }
        let (text, result) = clipboard.currentText()
        switch result {
        case .sent:
            server?.send(.clipboardText(text ?? ""))
            clipboardNotice = "Sent the clipboard to \(connected?.name ?? "your phone")."
            log("Sent clipboard text to the phone")
        case .empty: clipboardNotice = "The clipboard has no text to send."
        case .concealed: clipboardNotice = "Not sent: the clipboard holds a password or other private item."
        case .tooLarge: clipboardNotice = "Not sent: the copied text is too large (over 256 KB)."
        }
    }

    public func setClipboardEnabled(_ enabled: Bool) {
        settings.clipboardEnabled = enabled
        if !enabled { setClipboardAutoSend(false) }
    }

    public func setClipboardAutoSend(_ enabled: Bool) {
        settings.clipboardAutoSend = enabled && settings.clipboardEnabled
        settings.clipboardAutoSend ? startClipboardWatch() : clipboard.stopWatching()
    }

    private func startClipboardWatch() {
        clipboard.watch { [weak self] text in
            guard let self, self.settings.clipboardEnabled, self.phoneSupports(Feature.clipboard) else { return }
            self.server?.send(.clipboardText(text))
        }
    }

    // MARK: - Notifications

    public func dismissNotification(_ notification: PhoneNotification) {
        server?.send(.notificationDismiss(key: notification.key))
        removeNotification(key: notification.key)
    }

    public func clearNotifications() {
        notifications = []
        notifier.removeAll()
    }

    public func setNotificationsInMacCenter(_ enabled: Bool) {
        settings.notificationsInMacCenter = enabled
        guard enabled else { return }
        Task {
            let result = await notifier.requestAuthorization()
            if result != .allowed {
                settings.notificationsInMacCenter = false
                settingsNotice = result == .unavailable
                    ? "macOS notifications need the packaged M’AND app."
                    : "macOS blocked notifications for M’AND. Allow them in System Settings → Notifications."
            }
        }
    }

    private func removeNotification(key: String) {
        notifications.removeAll { $0.key == key }
        notifier.remove(key: key)
    }

    // MARK: - Screen mirroring

    public func startMirroring() { scrcpy.start(allowControl: settings.mirroringAllowsControl) }
    public func stopMirroring() { scrcpy.stop() }
    public func refreshMirroring() { scrcpy.refresh() }

    public func chooseScrcpy() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Choose the “scrcpy” program from the folder you downloaded."
        if panel.runModal() == .OK, let url = panel.url {
            settings.scrcpyPath = url.path
            scrcpy.setCustomPath(url.path)
        }
    }

    private func syncMirroring() {
        mirroringState = scrcpy.state
        mirroringOutput = scrcpy.recentOutput
    }

    // MARK: - Launch at login

    public var launchAtLogin: Bool { LaunchAtLogin.isEnabled }

    public func setLaunchAtLogin(_ enabled: Bool) {
        settingsNotice = LaunchAtLogin.set(enabled)
    }

    // MARK: - Event handling

    func apply(_ event: BridgeServer.Event) {
        switch event {
        case .listening(let port):
            serverStatus = .listening(port: port)
        case .listenerFailed(let reason):
            serverStatus = .failed(reason)
        case .advertising(let active, _):
            isAdvertising = active
        case .pairingWindowOpened(let invitation):
            self.invitation = invitation
        case .pairingWindowClosed:
            invitation = nil
        case .pairingUnavailable(let reason):
            invitation = nil
            pairingNotice = reason
        case .approvalNeeded(let request):
            pendingApproval = request
        case .pairingFinished(let name, let outcome):
            invitation = nil
            if pendingApproval != nil { pendingApproval = nil }
            pairingNotice = switch outcome {
            case "paired": "Paired with \(name)."
            case "timed out": "Pairing with \(name) timed out. Show a new QR code to try again."
            case "cancelled": "\(name) stopped pairing before it was approved."
            default: "Pairing with \(name) was declined."
            }
        case .devicesChanged(let devices):
            self.devices = devices
            if let current = connected, !devices.contains(where: { $0.fingerprint == current.fingerprint }) {
                connected = nil
            }
        case .phoneConnected(let device, let address, let features):
            connected = device
            connectedAddress = address
            phoneFeatures = features
            files?.connectionChanged(connected: features.contains(Feature.files))
        case .phoneDisconnected(let device, let reason):
            if connected?.fingerprint == device.fingerprint {
                connected = nil
                connectedAddress = nil
                phoneFeatures = []
                files?.connectionChanged(connected: false)
                notifications = []
                notifier.removeAll()
            }
            lastDisconnect = (device.name, reason, Date())
        case .textReceived(let text, _):
            appendChat(ChatLine(direction: .fromPhone, text: text, date: Date()))
        case .featureMessage(let message):
            applyFeature(message)
        case .log(let text):
            log(text)
        }
    }

    private func applyFeature(_ message: Message) {
        switch message {
        case .clipboardText(let text):
            guard settings.clipboardEnabled else { return }
            clipboard.apply(text)
            clipboardNotice = "Copied text from \(connected?.name ?? "your phone") to this Mac’s clipboard."
            log("Received clipboard text from the phone")
        case .deviceStatus(let battery, let charging):
            phoneStatus = PhoneStatus(battery: battery, charging: charging, updated: Date())
        case .notificationPosted(let notification):
            notifications.removeAll { $0.key == notification.key }
            notifications.insert(notification, at: 0)
            if notifications.count > Self.maxNotifications { notifications.removeLast() }
            if settings.notificationsInMacCenter { notifier.show(notification) }
        case .notificationRemoved(let key):
            removeNotification(key: key)
        default:
            break
        }
    }

    private func appendChat(_ line: ChatLine) {
        chat = Array((chat + [line]).suffix(Self.maxChatLines))
    }

    private func log(_ text: String) {
        log = Array((log + [LogLine(date: Date(), text: text)]).suffix(Self.maxLogLines))
    }
}

/// A value shared with background queues (the transfer queue reads the download folder).
final class LockedValue<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T { lock.withLock { value } }
    func set(_ newValue: T) { lock.withLock { value = newValue } }
}

/// Lets closures created before the server exists reach it later.
private final class ServerReference: @unchecked Sendable {
    weak var server: BridgeServer?
}
