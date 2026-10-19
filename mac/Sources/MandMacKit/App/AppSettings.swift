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

    enum Keys {
        static let downloadFolder = "downloadFolder"
        static let clipboardEnabled = "clipboardEnabled"
        static let clipboardAutoSend = "clipboardAutoSend"
        static let notificationsInMacCenter = "notificationsInMacCenter"
        static let mirroringAllowsControl = "mirroringAllowsControl"
        static let scrcpyPath = "scrcpyPath"
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
    }
}
