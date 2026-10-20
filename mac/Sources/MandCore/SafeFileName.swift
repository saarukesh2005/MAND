import Foundation

/// Turns an untrusted, peer-supplied file path into safe local path components (protocol §3a).
/// Both apps implement these exact rules and test them against `vectors.fileNames`.
///
/// Everything here works on Unicode scalars (code points), never on Swift `Character`s: a `/` followed
/// by a combining or zero-width character forms one Character that isn't equal to "/", which once
/// let a crafted name smuggle a separator past the split (path traversal).
public enum SafeFileName {
    public static let maxComponents = 32
    public static let maxComponentBytes = 255
    static let maxExtensionBytes = 16

    public enum Failure: Error, Equatable { case empty, traversal, tooDeep, invalid }

    public static func components(of path: String) throws(Failure) -> [String] {
        var result: [String] = []
        let parts = path.unicodeScalars.split(omittingEmptySubsequences: true) { $0 == "/" || $0 == "\\" }
        for raw in parts {
            let cleaned = clean(Array(raw))
            if cleaned.isEmpty || cleaned == "." { continue }
            if cleaned == ".." { throw .traversal }
            // Defence in depth: a component must never contain a separator or NUL.
            if cleaned.unicodeScalars.contains(where: { $0 == "/" || $0 == "\\" || $0 == "\0" }) { throw .invalid }
            result.append(cleaned)
        }
        if result.isEmpty { throw .empty }
        if result.count > maxComponents { throw .tooDeep }
        return result
    }

    static func clean(_ input: [Unicode.Scalar]) -> String {
        var scalars: [Unicode.Scalar] = []
        for scalar in input {
            switch scalar.properties.generalCategory {
            case .control, .format: continue
            default: scalars.append(scalar == ":" ? "_" : scalar)
            }
        }
        while scalars.first == " " { scalars.removeFirst() }
        while scalars.last == " " { scalars.removeLast() }
        let text = string(scalars)
        if text.isEmpty || text == "." || text == ".." { return text }
        if scalars.first == "." { scalars[0] = "_" }
        return truncate(scalars)
    }

    /// Cuts to 255 UTF-8 bytes by whole code points, keeping a short extension.
    static func truncate(_ scalars: [Unicode.Scalar]) -> String {
        guard string(scalars).utf8.count > maxComponentBytes else { return string(scalars) }
        var stem = scalars
        var ext: [Unicode.Scalar] = []
        if let dot = scalars.lastIndex(of: "."), dot > 0 {
            let candidate = Array(scalars[dot...])
            if string(candidate).utf8.count - 1 <= maxExtensionBytes {
                ext = candidate
                stem = Array(scalars[..<dot])
            }
        }
        let budget = maxComponentBytes - string(ext).utf8.count
        var kept: [Unicode.Scalar] = []
        var used = 0
        for scalar in stem {
            let size = String(scalar).utf8.count
            if used + size > budget { break }
            kept.append(scalar)
            used += size
        }
        return string(kept + ext)
    }

    /// `name`, or `name (2)`, `name (3)`… — the first one for which `exists` is false.
    public static func uniqueName(_ name: String, exists: (String) -> Bool) -> String {
        guard exists(name) else { return name }
        let scalars = Array(name.unicodeScalars)
        var stem = name
        var ext = ""
        if let dot = scalars.lastIndex(of: "."), dot > 0 {
            stem = string(Array(scalars[..<dot]))
            ext = string(Array(scalars[dot...]))
        }
        var n = 2
        while exists("\(stem) (\(n))\(ext)") { n += 1 }
        return "\(stem) (\(n))\(ext)"
    }

    private static func string(_ scalars: [Unicode.Scalar]) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// Joins safe components under `root` and confirms the result is still inside `root` after
    /// resolving every symlink that exists on disk (e.g. one placed inside the download folder).
    /// Returns nil if it would escape, or if the path runs through a broken symlink.
    public static func contained(_ components: [String], in root: URL) -> URL? {
        var url = root
        for component in components { url.appendPathComponent(component) }
        guard let rootPath = physicalPath(root), let target = physicalPath(url) else { return nil }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return target.hasPrefix(prefix) ? url : nil
    }

    /// The real on-disk path: `realpath` of the deepest part that exists, plus the not-yet-created rest.
    /// (Foundation's `resolvingSymlinksInPath` does nothing when the final item doesn't exist yet.)
    static func physicalPath(_ url: URL) -> String? {
        var existing = url.standardizedFileURL
        var tail: [String] = []
        while !itemExists(existing.path) {
            guard existing.path != "/" else { return nil }
            tail.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        guard let resolved = realpath(existing.path, nil) else { return nil } // broken symlink → reject
        defer { free(resolved) }
        let base = String(cString: resolved)
        return tail.isEmpty ? base : (base == "/" ? "" : base) + "/" + tail.joined(separator: "/")
    }

    /// True for anything at `path`, including a symlink whose target is missing.
    private static func itemExists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }
}
