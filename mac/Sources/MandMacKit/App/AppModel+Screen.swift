import Foundation
import MandCore

/// Built-in screen mirroring over Wi-Fi (view only): no USB cable, no developer options, nothing to install.
extension AppModel {
    public enum ScreenState: Equatable {
        case idle
        /// Asked the phone; waiting for the person to tap the notification and Start now.
        case asking(phone: String)
        case showing(phone: String, width: Int, height: Int, hasPicture: Bool)
        case ended(String)
    }

    /// Asks the selected phone to share its screen. The phone shows Android's own "Start now" prompt.
    public func startPhoneScreen() {
        guard let phone = selected, phone.supports(Feature.screen) else { return }
        server?.send(.screenRequest, to: phone.device.fingerprint)
        screenState = .asking(phone: phone.device.name)
        log("Asked \(phone.device.name) to share its screen")
    }

    /// Control the shared phone screen. Positions are fractions (0…1) of the picture.
    public func tapPhone(atX x: Double, y: Double) {
        sendControl(.controlTap(x: Self.scaled(x), y: Self.scaled(y)))
    }

    public func swipePhone(fromX x1: Double, y1: Double, toX x2: Double, y2: Double, seconds: Double) {
        let ms = Int((seconds * 1000).rounded()).clamped(to: 50...3_000)
        sendControl(.controlSwipe(x1: Self.scaled(x1), y1: Self.scaled(y1), x2: Self.scaled(x2), y2: Self.scaled(y2), ms: ms))
    }

    public func pressPhoneKey(_ key: Message.ControlKey) {
        sendControl(.controlKey(key))
    }

    private func sendControl(_ message: Message) {
        guard let phone = selected, phone.canControl, phone.supports(Feature.control),
              case .showing = screenState else { return }
        server?.send(message, to: phone.device.fingerprint)
    }

    static func scaled(_ fraction: Double) -> Int {
        Int((fraction.isFinite ? fraction : 0).clamped(to: 0...1) * Double(Message.controlScale))
    }

    public func stopPhoneScreen() {
        if let phone = selected, phone.supports(Feature.screen) {
            server?.send(.screenStop(reason: "user"), to: phone.device.fingerprint)
        }
        screenMirror?.reset()
        screenState = .idle
        if let fingerprint = selected?.device.fingerprint { update(fingerprint) { $0.canControl = false } }
    }

    func applyScreen(_ event: ScreenMirror.Event) {
        func name(_ fingerprint: Fingerprint) -> String {
            phones.first { $0.device.fingerprint == fingerprint }?.device.name ?? "Your phone"
        }
        switch event {
        case .started(let phone, let width, let height):
            screenState = .showing(phone: name(phone), width: width, height: height, hasPicture: false)
        case .firstPicture:
            if case .showing(let phone, let width, let height, _) = screenState {
                screenState = .showing(phone: phone, width: width, height: height, hasPicture: true)
            }
        case .stopped(let phone, let reason):
            screenState = .ended(reason == "user" ? "\(name(phone)) stopped sharing its screen."
                                                  : "Screen sharing ended (\(reason)).")
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
