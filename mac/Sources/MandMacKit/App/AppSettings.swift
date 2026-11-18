import Foundation
import Observation

/// User preferences, saved in UserDefaults. Private-by-default: sharing features start off.
@MainActor
@Observable
public final class AppSettings {
    private let defaults: UserDefaults

    public var downloadFolder: URL { didSet { defaults.set(downloadFolder.path, forKey: Keys.downloadFolder) } }
    public var clipboardEnabled: Bool { didSet { defaults.set(clipboardEnabled, forKey: Keys.clipboardEnabled) } }
    public var clipboardAutoSend: Bool { didSet { defaults.set(clipboardAutoSend, forKey: Keys.clipboardAutoSend) } }
    public var notificationsInMacCenter: Bool {
        didSet { defaults.set(notificationsInMacCenter, forKey: Keys.notificationsInMacCenter) }
    }
    public var mirroringAllowsControl: Bool {
        didSet { defaults.set(mirroringAllowsControl, forKey: Keys.mirroringAllowsControl) }
    }
    public var scrcpyPath: String? { didSet { defaults.set(scrcpyPath, forKey: Keys.scrcpyPath) } }
    public var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }
    /// Unofficial Quick Share receiving; off until the user turns it on.
    public var quickShareEnabled: Bool { didSet { defaults.set(quickShareEnabled, forKey: Keys.quickShareEnabled) } }
    /// Tap to Send (reads the notch light sensor through a private API); off until the user turns it on.
    public var tapEnabled: Bool { didSet { defaults.set(tapEnabled, forKey: Keys.tapEnabled) } }
    /// The person switched Tap to Send off on this Mac themselves, so it isn't switched back on automatically.
    public var tapTurnedOffByUser: Bool { didSet { defaults.set(tapTurnedOffByUser, forKey: Keys.tapTurnedOffByUser) } }
    /// Links shared from the phone open in the Mac's browser straight away (on by default: sharing is deliberate).
    public var openLinksFromPhone: Bool { didSet { defaults.set(openLinksFromPhone, forKey: Keys.openLinksFromPhone) } }
    /// Names the user gave paired phones on this Mac, by fingerprint (hex).
    public var deviceAliases: [String: String] { didSet { defaults.set(deviceAliases, forKey: Keys.deviceAliases) } }

    enum Keys {
        static let downloadFolder = "downloadFolder"
        static let clipboardEnabled = "clipboardEnabled"
        static let clipboardAutoSend = "clipboardAutoSend"
        static let notificationsInMacCenter = "notificationsInMacCenter"
        static let mirroringAllowsControl = "mirroringAllowsControl"
        static let scrcpyPath = "scrcpyPath"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let quickShareEnabled = "quickShareEnabled"
        static let tapEnabled = "tapEnabled"
        static let tapTurnedOffByUser = "tapTurnedOffByUser"
        static let openLinksFromPhone = "openLinksFromPhone"
        static let deviceAliases = "deviceAliases"
    }

    public static var defaultDownloadFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("M’AND", isDirectory: true)
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        downloadFolder = defaults.string(forKey: Keys.downloadFolder).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Self.defaultDownloadFolder
        clipboardEnabled = defaults.bool(forKey: Keys.clipboardEnabled)
        clipboardAutoSend = defaults.bool(forKey: Keys.clipboardAutoSend)
        notificationsInMacCenter = defaults.bool(forKey: Keys.notificationsInMacCenter)
        mirroringAllowsControl = defaults.bool(forKey: Keys.mirroringAllowsControl)
        scrcpyPath = defaults.string(forKey: Keys.scrcpyPath)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        quickShareEnabled = defaults.bool(forKey: Keys.quickShareEnabled)
        tapEnabled = defaults.bool(forKey: Keys.tapEnabled)
        tapTurnedOffByUser = defaults.bool(forKey: Keys.tapTurnedOffByUser)
        openLinksFromPhone = defaults.object(forKey: Keys.openLinksFromPhone) as? Bool ?? true
        deviceAliases = defaults.dictionary(forKey: Keys.deviceAliases) as? [String: String] ?? [:]
    }
}
