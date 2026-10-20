import Foundation

/// Launches and manages scrcpy (github.com/Genymobile/scrcpy, Apache-2.0) for screen mirroring.
/// M’AND doesn't bundle or download scrcpy; it finds a copy the user installed.
@MainActor
public final class ScrcpyManager {
    public enum State: Equatable {
        case notInstalled
        case ready(path: String)
        case running
        case failed(String)
    }

    public private(set) var state: State = .notInstalled
    public private(set) var recentOutput: [String] = []
    public var onChange: (() -> Void)?

    private var process: Process?
    private var customPath: String?

    public init(customPath: String? = nil) {
        self.customPath = customPath
        refresh()
    }

    public static let downloadPage = URL(string: "https://github.com/Genymobile/scrcpy/releases/latest")!

    /// Where scrcpy is usually found: Homebrew, or an official release unzipped into an Applications folder.
    /// Privacy-protected folders (Downloads, Documents, Desktop) are never scanned automatically: that
    /// would make macOS show an access prompt at launch. Use "Choose scrcpy…" for other locations.
    nonisolated static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        var paths = ["/opt/homebrew/bin/scrcpy", "/usr/local/bin/scrcpy"]
        for folder in [home.appendingPathComponent("Applications"), URL(fileURLWithPath: "/Applications")] {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for entry in entries.sorted().reversed() where entry.lowercased().hasPrefix("scrcpy") {
                paths.append(folder.appendingPathComponent(entry).appendingPathComponent("scrcpy").path)
            }
        }
        return paths
    }

    public func setCustomPath(_ path: String?) {
        customPath = path
        refresh()
    }

    public func refresh() {
        guard process == nil else { return }
        let all = (customPath.map { [$0] } ?? []) + Self.candidates()
        if let found = all.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            state = .ready(path: found)
        } else {
            state = .notInstalled
        }
        onChange?()
    }

    /// Arguments for scrcpy. View-only unless `allowControl` is true.
    nonisolated static func arguments(allowControl: Bool, title: String) -> [String] {
        var args = ["--window-title=\(title)"]
        if !allowControl { args.append("--no-control") }
        else { args.append("--stay-awake") }
        return args
    }

    public func start(allowControl: Bool) {
        guard case .ready(let path) = state else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = Self.arguments(allowControl: allowControl, title: "M’AND · Phone screen")
        var environment = ProcessInfo.processInfo.environment
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent()
        let bundledADB = folder.appendingPathComponent("adb").path
        if FileManager.default.isExecutableFile(atPath: bundledADB) { environment["ADB"] = bundledADB }
        environment["PATH"] = [folder.path, "/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin"]
            .joined(separator: ":")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            guard !lines.isEmpty else { return }
            Task { @MainActor in
                guard let self else { return }
                self.recentOutput = Array((self.recentOutput + lines).suffix(20))
                self.onChange?()
            }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in
                guard let self else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                if status == 0 || status == 15 {
                    self.refresh()
                } else {
                    self.state = .failed(Self.explain(self.recentOutput))
                    self.onChange?()
                }
            }
        }
        do {
            recentOutput = []
            try process.run()
            self.process = process
            state = .running
        } catch {
            state = .failed("Couldn’t start scrcpy: \(error.localizedDescription)")
        }
        onChange?()
    }

    public func stop() {
        process?.terminate()
    }

    /// Turns scrcpy's technical output into a plain explanation.
    nonisolated static func explain(_ output: [String]) -> String {
        let text = output.joined(separator: "\n").lowercased()
        if text.contains("no devices") || text.contains("could not find any adb device") {
            return "No phone found. Connect it with a USB cable and turn on USB debugging (Developer options)."
        }
        if text.contains("unauthorized") {
            return "Tap “Allow USB debugging” on the phone, then try again."
        }
        if text.contains("more than one") {
            return "More than one Android device is connected. Disconnect the others and try again."
        }
        return output.last ?? "Screen mirroring stopped unexpectedly."
    }
}
