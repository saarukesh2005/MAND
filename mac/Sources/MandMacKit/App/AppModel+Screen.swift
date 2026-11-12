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

    public func stopPhoneScreen() {
        if let phone = selected, phone.supports(Feature.screen) {
            server?.send(.screenStop(reason: "user"), to: phone.device.fingerprint)
        }
        screenMirror?.reset()
        screenState = .idle
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
