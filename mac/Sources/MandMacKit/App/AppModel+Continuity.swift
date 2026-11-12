import AppKit
import Foundation
import MandCore

/// Find my phone, links between devices, and renaming phones on this Mac.
extension AppModel {
    // MARK: - Find my phone

    /// Makes the selected phone play a loud sound (even on silent) until stopped or found.
    public func ringPhone() {
        guard let phone = selected, phone.supports(Feature.find) else { return }
        server?.send(.findRing, to: phone.device.fingerprint)
        log("Asked \(phone.device.name) to ring")
    }

    public func stopRingingPhone() {
        guard let phone = selected, phone.supports(Feature.find) else { return }
        server?.send(.findStop, to: phone.device.fingerprint)
    }

    // MARK: - Links

    public enum LinkSendResult: Equatable { case sent, invalid, notConnected }

    /// Sends a web link to the selected phone, which offers to open it.
    @discardableResult
    public func sendLink(_ text: String) -> LinkSendResult {
        let url = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LinkRules.isValid(url) else {
            linkNotice = "That isn’t a web link (it must start with http:// or https://)."
            return .invalid
        }
        guard let phone = selected, phone.supports(Feature.link) else {
            linkNotice = "Connect a phone with M’AND 0.5 or later to send links."
            return .notConnected
        }
        server?.send(.linkOpen(url: url, title: nil), to: phone.device.fingerprint)
        linkNotice = "Sent the link to \(phone.device.name). Tap the notification on the phone to open it."
        return .sent
    }

    /// A web link on this Mac's clipboard, if there is one (to prefill "Send link").
    public var clipboardLink: String? {
        guard let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), LinkRules.isValid(text) else { return nil }
        return text
    }

    func receiveLink(_ url: String, title: String?, from device: PairedDevice) {
        // The codec already accepts only http(s) links; check again before handing it to the system.
        guard LinkRules.isValid(url), let link = URL(string: url),
              let scheme = link.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        let label = title ?? link.host() ?? url
        log("Link from \(device.name): \(label)")
        if settings.openLinksFromPhone {
            NSWorkspace.shared.open(link)
            linkNotice = "Opened “\(label)” from \(device.name)."
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
            linkNotice = "\(device.name) shared “\(label)”. The link is on your clipboard."
        }
    }

    // MARK: - Recovery

    /// Reads the paired-phone list again (after the user allowed Keychain access).
    public func retryTrustedList() {
        trustedListProblem = nil
        server?.reloadDevices()
    }

    // MARK: - Renaming

    /// Gives a paired phone a name on this Mac. An empty name goes back to the phone's own name.
    public func renameDevice(_ device: PairedDevice, to newName: String) {
        let name = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        var aliases = settings.deviceAliases
        aliases[device.fingerprint.hex] = name.isEmpty ? nil : name
        settings.deviceAliases = aliases
        // Re-apply the stored list so a removed alias falls back to the phone's own name.
        apply(.devicesChanged(storedDevices))
        log(name.isEmpty ? "Restored the phone’s own name" : "Renamed a phone to \(name)")
    }

    func aliased(_ device: PairedDevice) -> PairedDevice {
        guard let alias = settings.deviceAliases[device.fingerprint.hex], alias != device.name else { return device }
        return PairedDevice(fingerprint: device.fingerprint, name: alias, pairedAt: device.pairedAt,
                            lastSeen: device.lastSeen, lastAddress: device.lastAddress)
    }
}
