import Foundation
import MandCore
import UserNotifications

/// Shows phone notifications in macOS Notification Center (optional; the in-app list always works).
@MainActor
public final class MacNotifier {
    public enum Authorization: Equatable { case unknown, allowed, denied, unavailable }

    public private(set) var authorization: Authorization = .unknown

    /// UNUserNotificationCenter only works inside a real app bundle (not `swift run`).
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    public init() {}

    public func requestAuthorization() async -> Authorization {
        guard let center else {
            authorization = .unavailable
            return authorization
        }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            authorization = granted ? .allowed : .denied
        } catch {
            authorization = .denied
        }
        return authorization
    }

    public func show(_ notification: PhoneNotification) {
        guard authorization == .allowed, let center else { return }
        let content = UNMutableNotificationContent()
        content.title = [notification.appName, notification.title].compactMap { $0 }.joined(separator: " · ")
        content.body = notification.text ?? ""
        content.threadIdentifier = notification.app
        let request = UNNotificationRequest(identifier: Self.identifier(notification.key), content: content, trigger: nil)
        center.add(request)
    }

    /// A general alert (e.g. an incoming call). `identifier` lets it be removed later.
    public func show(title: String, body: String, identifier: String) {
        guard authorization == .allowed, let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    public func remove(identifier: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    public func remove(key: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [Self.identifier(key)])
    }

    public func removeAll() {
        center?.removeAllDeliveredNotifications()
    }

    static func identifier(_ key: String) -> String { "phone." + key }
}
