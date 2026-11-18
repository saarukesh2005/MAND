import AppKit
import Foundation
import MandCore
import Observation

/// Everything the Mac UI shows, derived only from real server events.
/// Several phones can be connected at once; actions go to the `selected` phone.
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
        public let deviceName: String
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

        /// Readings older than this are shown as "last known".
        public static let staleAfter: TimeInterval = 10 * 60
        public func isStale(at now: Date = Date()) -> Bool { now.timeIntervalSince(updated) > Self.staleAfter }
    }

    public struct CallInfo: Equatable {
        public let state: Message.CallState
        public let caller: String?
        public let since: Date
    }

    /// A phone with a live, trusted connection.
    public struct ConnectedPhone: Identifiable, Equatable {
        public internal(set) var device: PairedDevice
        public var address: String?
        public var features: Set<String>
        public var status: PhoneStatus?
        public var notifications: [PhoneNotification] = []
        public var call: CallInfo?
        public var info: DeviceInfo?
        public var latencyMs: Int?
        /// The phone said it's playing the find-my-phone sound.
        public var isRinging = false
        /// The phone accepts taps and swipes from this Mac (only while it shares its screen).
        public var canControl = false
        /// The phone has Tap to Send switched on (its Accessibility service is running).
        public var tapReady = false
        public let connectedAt: Date

        public var id: String { device.fingerprint.hex }
        public func supports(_ feature: String) -> Bool { features.contains(feature) }
    }

    /// A transfer row for the UI: live (from a transfer engine) or remembered history.
    public struct TransferEntry: Identifiable, Equatable {
        public let item: FileTransferService.Item
        public let deviceName: String
        public var id: String { item.id }
    }

    public static let maxLogLines = 200
    public static let maxChatLines = 100
    public static let maxNotifications = 200

    // Connection
    public private(set) var serverStatus: ServerStatus = .starting
    public private(set) var isAdvertising = false
    public private(set) var devices: [PairedDevice] = []
    /// The paired list as stored (phones' own names), before this Mac's renames.
    private(set) var storedDevices: [PairedDevice] = []
    public private(set) var phones: [ConnectedPhone] = []
    public var selectedPhoneID: String?
    public private(set) var lastDisconnect: (name: String, reason: String, date: Date)?
    public private(set) var invitation: PairingInvitation?
    public private(set) var pairingNotice: String?
    public private(set) var chat: [ChatLine] = []
    public private(set) var log: [LogLine] = []
    public private(set) var startupError: String?
    public var pendingApproval: BridgeServer.PairingRequest?

    // Features
    public private(set) var liveTransfers: [TransferEntry] = []
    public private(set) var history: [TransferRecord] = []
    public private(set) var clipboardNotice: String?
    public private(set) var mirroringState: ScrcpyManager.State = .notInstalled
    public private(set) var mirroringOutput: [String] = []
    public private(set) var settingsNotice: String?
    /// Last Tap to Send outcome, shown in Home and Settings.
    public private(set) var tapNotice: String?
    /// nil until Tap to Send has been switched on once and the sensor was checked.
    public private(set) var tapSensorAvailable: Bool?
    /// Set when the paired-phone list can't be read (shown on Home with a Try Again button).
    public internal(set) var trustedListProblem: String?
    /// Built-in Wi-Fi screen mirroring state, and the mirror that displays the picture.
    public internal(set) var screenState: ScreenState = .idle
    public private(set) var screenMirror: ScreenMirror?
    /// Last link sent or received, shown in Home.
    public internal(set) var linkNotice: String?
    public let settings: AppSettings

    public let macName: String
    private(set) var server: BridgeServer?
    private var fileServices: [Fingerprint: FileTransferService] = [:]
    private var liveByDevice: [Fingerprint: [FileTransferService.Item]] = [:]
    private let historyStore: TransferHistoryStore
    private let clipboard = ClipboardService()
    private let notifier = MacNotifier()
    private let scrcpy: ScrcpyManager
    private let downloadFolderBox = LockedValue(AppSettings.defaultDownloadFolder)
    private var wakeObserver: NSObjectProtocol?
    private var tap: TapCoordinator?
    /// Phones whose tap just passed; their next "Tap …" file opens automatically.
    private var tapExpectingFile: [Fingerprint: Date] = [:]
    /// Called on every tap step so the app can show the notch pill.
    public var onTapPhase: ((TapPhase) -> Void)?

    public init(macName: String, settings: AppSettings = AppSettings(),
                historyStore: TransferHistoryStore = TransferHistoryStore()) {
        self.macName = macName
        self.settings = settings
        self.historyStore = historyStore
        scrcpy = ScrcpyManager(customPath: settings.scrcpyPath)
        history = historyStore.load()
        scrcpy.onChange = { [weak self] in self?.syncMirroring() }
        syncMirroring()
    }

    // MARK: - Derived state (the selected phone)

    public var isConnected: Bool { !phones.isEmpty }

    /// The phone that actions (send files, clipboard, test message) go to.
    public var selected: ConnectedPhone? {
        phones.first { $0.id == selectedPhoneID } ?? phones.last
    }

    public var connected: PairedDevice? { selected?.device }
    public var connectedAddress: String? { selected?.address }
    public var phoneStatus: PhoneStatus? { selected?.status }
    public var notifications: [PhoneNotification] { selected?.notifications ?? [] }
    public var macFingerprint: Fingerprint? { server?.identity.fingerprint }

    /// The first phone with a ringing call, if any.
    public var ringingPhone: ConnectedPhone? { phones.first { $0.call?.state == .ringing } }

    public func phoneSupports(_ feature: String) -> Bool { selected?.supports(feature) ?? false }

    /// Live transfers first, then remembered history (newest first).
    public var transfers: [TransferEntry] {
        let liveIDs = Set(liveTransfers.map(\.id))
        let past = history.reversed().filter { !liveIDs.contains($0.id) }
            .map { TransferEntry(item: $0.item, deviceName: $0.deviceName) }
        return liveTransfers + past
    }

    public func isConnected(_ device: PairedDevice) -> Bool {
        phones.contains { $0.device.fingerprint == device.fingerprint }
    }

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
        downloadFolderBox.set(settings.downloadFolder)
        let routes = FileRoutes()
        let serverRef = ServerReference()
        let tap = TapCoordinator(
            send: { message, phone in serverRef.server?.send(message, to: phone) },
            onEvent: { [weak self] event in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyTap(event) } }
            })
        let mirror = ScreenMirror { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.applyScreen(event) } }
        }
        screenMirror = mirror
        let server = BridgeServer(identity: identity, store: store, deviceName: macName) { [weak self] event in
            // File and tap messages go straight to their queues; everything else to the UI, in order.
            if case .featureMessage(let message, let device) = event {
                if message.feature == Feature.files, let service = routes.service(for: device.fingerprint) {
                    service.handle(message)
                    return
                }
                if message.feature == Feature.tap {
                    tap.handle(message, from: device.fingerprint)
                    return
                }
                if message.feature == Feature.screen {
                    mirror.handle(message, from: device.fingerprint) // video frames never touch the main thread
                    return
                }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(event) } }
        }
        self.fileRoutes = routes
        self.server = server
        serverRef.server = server
        self.tap = tap
        tap.setEnabled(settings.tapEnabled)
        server.start()
        if settings.clipboardAutoSend { startClipboardWatch() }
        if settings.notificationsInMacCenter { Task { _ = await notifier.requestAuthorization() } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak server] _ in
            server?.dropStaleSessions()
        }
    }

    private var fileRoutes: FileRoutes?

    public func stop() {
        tap?.setEnabled(false)
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

    public func select(_ phone: ConnectedPhone) { selectedPhoneID = phone.id }

    /// Returns false (and sends nothing) if the text is empty, too long, or no phone is connected.
    @discardableResult
    public func sendTestMessage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let phone = selected, !trimmed.isEmpty, trimmed.utf8.count <= Message.maxTextBytes else { return false }
        server?.sendText(trimmed, to: phone.device.fingerprint)
        appendChat(ChatLine(direction: .fromMac, text: trimmed, date: Date(), deviceName: phone.device.name))
        return true
    }

    public func forget(_ device: PairedDevice) {
        server?.forget(device.fingerprint)
    }

    // MARK: - Files

    public func sendFiles(_ urls: [URL]) {
        guard let phone = selected else { return }
        fileService(for: phone.device).send(urls: urls)
    }

    public func cancelTransfer(_ id: String) { owner(of: id)?.cancel(id: id) }
    public func retryTransfer(_ id: String) { owner(of: id)?.retry(id: id) }

    public func clearFinishedTransfers() {
        fileServices.values.forEach { $0.clearFinished() }
        history = []
        historyStore.save([])
    }

    /// Records a transfer that arrived another way (Quick Share) in the shared history.
    public func recordReceived(files: [URL], from sender: String) {
        let records = files.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            let item = FileTransferService.Item(id: UUID().uuidString, name: url.lastPathComponent, direction: .incoming,
                                                size: size, transferred: size, bytesPerSecond: 0, state: .done, savedURL: url)
            return TransferRecord(item: item, deviceName: "\(sender) · Quick Share", finishedAt: Date())
        }
        history = Array((history + records).suffix(TransferHistoryStore.limit))
        historyStore.save(history)
    }

    /// The folder received files are saved in (read by other receivers, e.g. Quick Share).
    public nonisolated var downloadFolderProvider: @Sendable () -> URL {
        let box = downloadFolderBox
        return { box.get() }
    }

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

    /// One transfer engine per phone, kept after disconnects so interrupted transfers can resume.
    private func fileService(for device: PairedDevice) -> FileTransferService {
        let fingerprint = device.fingerprint
        if let existing = fileServices[fingerprint] { return existing }
        let folder = downloadFolderBox
        let serverBox = ServerReference()
        serverBox.server = server
        let service = FileTransferService(
            destination: { folder.get() },
            send: { message, completion in
                guard let server = serverBox.server else { completion?(false); return }
                server.send(message, to: fingerprint, completion: completion)
            },
            onChange: { [weak self] items in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.transfersChanged(items, device: device) } }
            })
        fileServices[fingerprint] = service
        fileRoutes?.set(service, for: fingerprint)
        if fileServices.count == 1 { service.cleanUpPartials() }
        return service
    }

    private func owner(of id: String) -> FileTransferService? {
        liveByDevice.first { $0.value.contains { $0.id == id } }.flatMap { fileServices[$0.key] }
    }

    private func transfersChanged(_ items: [FileTransferService.Item], device: PairedDevice) {
        liveByDevice[device.fingerprint] = items.filter { !$0.isFinished }
        let known = Set(history.map(\.id))
        let finished = items.filter { $0.isFinished && !known.contains($0.id) }
        finished.forEach { showTapResultIfExpected($0, from: device.fingerprint) }
        if !finished.isEmpty {
            history = Array((history + finished.map {
                TransferRecord(item: $0, deviceName: device.name, finishedAt: Date())
            }).suffix(TransferHistoryStore.limit))
            historyStore.save(history)
        }
        let names = Dictionary(uniqueKeysWithValues: devices.map { ($0.fingerprint, $0.name) })
        liveTransfers = liveByDevice.flatMap { fingerprint, items in
            items.map { TransferEntry(item: $0, deviceName: names[fingerprint] ?? device.name) }
        }
    }

    // MARK: - Clipboard

    /// Sends the Mac clipboard to the selected phone (deliberate user action).
    public func sendClipboard() {
        guard settings.clipboardEnabled else {
            clipboardNotice = "Turn on clipboard sharing first."
            return
        }
        guard let phone = selected, phone.supports(Feature.clipboard) else {
            clipboardNotice = "Connect a phone with clipboard sharing to send."
            return
        }
        let (text, result) = clipboard.currentText()
        switch result {
        case .sent:
            server?.send(.clipboardText(text ?? ""), to: phone.device.fingerprint)
            clipboardNotice = "Sent the clipboard to \(phone.device.name)."
            log("Sent clipboard text to \(phone.device.name)")
        case .empty: clipboardNotice = "The clipboard has no text to send."
        case .concealed: clipboardNotice = "Not sent: the clipboard holds a password or other private item."
        case .tooLarge: clipboardNotice = "Not sent: the copied text is too large (over 256 KB)."
        }
    }

    // MARK: - Tap to Send

    /// What the notch pill shows during a tap (see `onTapPhase`).
    public enum TapPhase: Equatable {
        case holding
        case sent(phone: String)
        case failed(String)
    }

    /// Ready on this Mac: switched on and the notch light sensor is readable.
    public var macTapReady: Bool { settings.tapEnabled && tapSensorAvailable != false }

    /// Switched by the person (Settings or Home). Turning it off is remembered, so it isn't turned back on for them.
    public func setTapEnabled(_ enabled: Bool) {
        settings.tapTurnedOffByUser = !enabled
        applyTapEnabled(enabled)
    }

    private func applyTapEnabled(_ enabled: Bool) {
        settings.tapEnabled = enabled
        tapNotice = nil
        tap?.setEnabled(enabled)
        tellPhonesTapReadiness()
    }

    /// The phone just switched Tap to Send on: switch the Mac on too, so there's only one place to set it up.
    func autoEnableTap() {
        guard !settings.tapEnabled, !settings.tapTurnedOffByUser, tapSensorAvailable != false else { return }
        applyTapEnabled(true)
        log("Tap to Send switched on because your phone is ready")
    }

    private func tellPhonesTapReadiness() {
        for phone in phones where phone.supports(Feature.tap) {
            server?.send(.tapReady(on: macTapReady), to: phone.device.fingerprint)
        }
    }

    private func applyTap(_ event: TapCoordinator.Event) {
        func name(_ fingerprint: Fingerprint?) -> String {
            phones.first { $0.device.fingerprint == fingerprint }?.device.name ?? "Your phone"
        }
        switch event {
        case .availability(let sensor):
            let changed = tapSensorAvailable != sensor
            tapSensorAvailable = sensor
            if changed { tellPhonesTapReadiness() }
        case .roundStarted:
            tapNotice = "Keep holding your phone on the notch…"
            onTapPhase?(.holding)
        case .passed(let phone):
            tapExpectingFile[phone] = Date()
            tapNotice = "Got it! \(name(phone)) is sending what’s on its screen."
            onTapPhase?(.sent(phone: name(phone)))
        case .declined(_, let why), .failed(_, let why):
            guard !["other-phone", "stopped", "declined"].contains(why) else { return }
            let tip = Self.tapReason(why)
            tapNotice = tip
            onTapPhase?(.failed(tip))
        }
    }

    /// One short, friendly instruction per failure, in the same words as the phone.
    public static func tapReason(_ code: String) -> String {
        switch code {
        case "not-seen", "no-light-sent", "no-key-on", "capture-failed":
            "Touch the top of your phone’s screen right on the black notch."
        case "stayed-lit", "too-far", "weak":
            "Press the phone flat against the notch."
        case "timeout", "no-key-off", "phone-left":
            "Hold still a little longer, until the phone buzzes."
        case "off": "Turn on Tap to Send on your phone."
        case "screen-off", "locked": "Unlock your phone first."
        case "paused-app": "Tap to Send is off in this app (banking apps are skipped)."
        case "secure-screen": "This screen is private, so it can’t be sent."
        case "busy": "Wait a second and try again."
        default: "That didn’t work. Try again."
        }
    }

    /// After a passed tap, the phone sends a "Tap …" picture: open it in front of the person and copy it.
    private func showTapResultIfExpected(_ item: FileTransferService.Item, from phone: Fingerprint) {
        guard item.direction == .incoming, case .done = item.state, item.name.hasPrefix("Tap "),
              let since = tapExpectingFile[phone], Date().timeIntervalSince(since) < 60,
              let url = item.savedURL else { return }
        tapExpectingFile[phone] = nil
        if let image = NSImage(contentsOf: url) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
        NSWorkspace.shared.open(url)
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
            guard let self, self.settings.clipboardEnabled,
                  let phone = self.selected, phone.supports(Feature.clipboard) else { return }
            self.server?.send(.clipboardText(text), to: phone.device.fingerprint)
        }
    }

    // MARK: - Notifications

    public func dismissNotification(_ notification: PhoneNotification) {
        guard let phone = selected else { return }
        server?.send(.notificationDismiss(key: notification.key), to: phone.device.fingerprint)
        update(phone.device.fingerprint) { $0.notifications.removeAll { $0.key == notification.key } }
        notifier.remove(key: notification.key)
    }

    public func clearNotifications() {
        guard let phone = selected else { return }
        update(phone.device.fingerprint) { $0.notifications = [] }
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

    // MARK: - Calls

    /// Answers or declines the ringing call on `phone`. The call audio stays on the phone.
    public func respondToCall(on phone: ConnectedPhone, answer: Bool) {
        server?.send(.callAction(answer ? .answer : .decline), to: phone.device.fingerprint)
        log("\(answer ? "Answered" : "Declined") a call on \(phone.device.name)")
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
            storedDevices = devices
            self.devices = devices.map(aliased)
            let trusted = Set(devices.map(\.fingerprint))
            phones.removeAll { !trusted.contains($0.device.fingerprint) }
            for device in self.devices { update(device.fingerprint) { $0.device = device } }
        case .phoneConnected(let original, let address, let features):
            let device = aliased(original)
            phones.removeAll { $0.device.fingerprint == device.fingerprint }
            phones.append(ConnectedPhone(device: device, address: address, features: features, connectedAt: Date()))
            selectedPhoneID = selectedPhoneID ?? device.fingerprint.hex
            if features.contains(Feature.files) { fileService(for: device).connectionChanged(connected: true) }
            tap?.phoneConnected(device.fingerprint, supportsTap: features.contains(Feature.tap))
            if features.contains(Feature.tap) { server?.send(.tapReady(on: macTapReady), to: device.fingerprint) }
        case .phoneDisconnected(let device, let reason):
            if let phone = phones.first(where: { $0.device.fingerprint == device.fingerprint }) {
                phone.notifications.forEach { notifier.remove(key: $0.key) }
                notifier.remove(identifier: Self.callAlertID(phone))
            }
            phones.removeAll { $0.device.fingerprint == device.fingerprint }
            if selectedPhoneID == device.fingerprint.hex { selectedPhoneID = phones.last?.id }
            fileServices[device.fingerprint]?.connectionChanged(connected: false)
            tap?.phoneDisconnected(device.fingerprint)
            if case .showing(let name, _, _, _) = screenState, name == aliased(device).name {
                screenMirror?.reset()
                screenState = .ended("\(name) disconnected.")
            } else if case .asking(let name) = screenState, name == aliased(device).name {
                screenState = .idle
            }
            lastDisconnect = (aliased(device).name, reason, Date())
        case .textReceived(let text, let device):
            appendChat(ChatLine(direction: .fromPhone, text: text, date: Date(), deviceName: aliased(device).name))
        case .featureMessage(let message, let device):
            applyFeature(message, from: aliased(device))
        case .trustedListProblem(let problem):
            trustedListProblem = problem
        case .latency(let device, let milliseconds):
            update(device.fingerprint) { $0.latencyMs = milliseconds }
        case .log(let text):
            log(text)
        }
    }

    private func applyFeature(_ message: Message, from device: PairedDevice) {
        let fingerprint = device.fingerprint
        switch message {
        case .clipboardText(let text):
            guard settings.clipboardEnabled else { return }
            clipboard.apply(text)
            clipboardNotice = "Copied text from \(device.name) to this Mac’s clipboard."
            log("Received clipboard text from \(device.name)")
        case .deviceStatus(let battery, let charging):
            update(fingerprint) { $0.status = PhoneStatus(battery: battery, charging: charging, updated: Date()) }
        case .notificationPosted(let notification):
            update(fingerprint) { phone in
                phone.notifications.removeAll { $0.key == notification.key }
                phone.notifications.insert(notification, at: 0)
                if phone.notifications.count > Self.maxNotifications { phone.notifications.removeLast() }
            }
            if settings.notificationsInMacCenter { notifier.show(notification) }
        case .notificationRemoved(let key):
            update(fingerprint) { $0.notifications.removeAll { $0.key == key } }
            notifier.remove(key: key)
        case .deviceInfo(let info):
            update(fingerprint) { $0.info = info }
        case .findState(let ringing):
            update(fingerprint) { $0.isRinging = ringing }
        case .controlState(let available):
            update(fingerprint) { $0.canControl = available }
        case .tapReady(let on):
            update(fingerprint) { $0.tapReady = on }
            if on { autoEnableTap() }
        case .linkOpen(let url, let title):
            receiveLink(url, title: title, from: device)
        case .callState(let state, let caller):
            update(fingerprint) { $0.call = state == .idle ? nil : CallInfo(state: state, caller: caller, since: Date()) }
            guard let phone = phones.first(where: { $0.device.fingerprint == fingerprint }) else { return }
            if state == .ringing {
                notifier.show(title: "Incoming call on \(device.name)", body: caller ?? "Unknown caller",
                              identifier: Self.callAlertID(phone))
            } else {
                notifier.remove(identifier: Self.callAlertID(phone))
            }
        default:
            break
        }
    }

    private static func callAlertID(_ phone: ConnectedPhone) -> String { "call." + phone.id }

    func update(_ fingerprint: Fingerprint, _ change: (inout ConnectedPhone) -> Void) {
        guard let index = phones.firstIndex(where: { $0.device.fingerprint == fingerprint }) else { return }
        change(&phones[index])
    }

    private func appendChat(_ line: ChatLine) {
        chat = Array((chat + [line]).suffix(Self.maxChatLines))
    }

    func log(_ text: String) {
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
final class ServerReference: @unchecked Sendable {
    weak var server: BridgeServer?
}

/// Thread-safe map from phone to its transfer engine, read on the server queue.
final class FileRoutes: @unchecked Sendable {
    private let lock = NSLock()
    private var services: [Fingerprint: FileTransferService] = [:]
    func service(for fingerprint: Fingerprint) -> FileTransferService? { lock.withLock { services[fingerprint] } }
    func set(_ service: FileTransferService, for fingerprint: Fingerprint) { lock.withLock { services[fingerprint] = service } }
}
