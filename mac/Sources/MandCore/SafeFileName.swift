import Foundation

/// Turns an untrusted, peer-supplied file path into safe local path components (protocol §3a).
/// Both apps implement these exact rules and test them against `vectors.fileNames`.
public enum SafeFileName {
    public static let maxComponents = 32
    public static let maxComponentBytes = 255
    static let maxExtensionBytes = 16

    public enum Failure: Error, Equatable { case empty, traversal, tooDeep }

    public static func components(of path: String) throws(Failure) -> [String] {
        var result: [String] = []
        for raw in path.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "/" || $0 == "\\" }) {
            let cleaned = clean(String(raw))
            if cleaned.isEmpty || cleaned == "." { continue }
            if cleaned == ".." { throw .traversal }
            result.append(cleaned)
        }
        if result.isEmpty { throw .empty }
        if result.count > maxComponents { throw .tooDeep }
        return result
    }

    static func clean(_ component: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in component.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format: continue
            default: scalars.append(scalar == ":" ? "_" : scalar)
            }
        }
        var text = String(scalars)
        while text.hasPrefix(" ") { text.removeFirst() }
        while text.hasSuffix(" ") { text.removeLast() }
        if text == "." || text == ".." || text.isEmpty { return text }
        if text.hasPrefix(".") { text = "_" + text.dropFirst() }
        return truncate(text)
    }

    /// Cuts to 255 UTF-8 bytes by whole code points, keeping a short extension.
    static func truncate(_ text: String) -> String {
        guard text.utf8.count > maxComponentBytes else { return text }
        var stem = text
        var ext = ""
        if let dot = text.lastIndex(of: "."), dot > text.startIndex {
            let candidate = String(text[dot...])
            if candidate.utf8.count - 1 <= maxExtensionBytes {
                ext = candidate
                stem = String(text[..<dot])
            }
        }
        let budget = maxComponentBytes - ext.utf8.count
        var kept = String.UnicodeScalarView()
        var used = 0
        for scalar in stem.unicodeScalars {
            let size = String(scalar).utf8.count
            if used + size > budget { break }
            kept.append(scalar)
            used += size
        }
        return String(kept) + ext
    }

    /// `name`, or `name (2)`, `name (3)`… — the first one for which `exists` is false.
    public static func uniqueName(_ name: String, exists: (String) -> Bool) -> String {
        guard exists(name) else { return name }
        var stem = name
        var ext = ""
        if let dot = name.lastIndex(of: "."), dot > name.startIndex {
            stem = String(name[..<dot])
            ext = String(name[dot...])
        }
        var n = 2
        while exists("\(stem) (\(n))\(ext)") { n += 1 }
        return "\(stem) (\(n))\(ext)"
    }
}
