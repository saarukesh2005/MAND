import ServiceManagement

/// Opens M’AND when you log in, using macOS's standard login-item mechanism.
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns an error message if macOS refused, or nil on success.
    @discardableResult
    public static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "macOS didn’t allow this: \(error.localizedDescription). You can add M’AND in System Settings → General → Login Items."
        }
    }
}
