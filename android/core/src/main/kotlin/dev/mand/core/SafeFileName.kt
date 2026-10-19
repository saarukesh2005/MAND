package dev.mand.core

/**
 * Turns an untrusted, peer-supplied file path into safe local path components (protocol §3a).
 * Mirrors mac/Sources/MandCore/SafeFileName.swift; both are tested against `vectors.fileNames`.
 */
object SafeFileName {
    const val MAX_COMPONENTS = 32
    const val MAX_COMPONENT_BYTES = 255
    private const val MAX_EXTENSION_BYTES = 16

    class Failure(reason: String) : Exception(reason)

    fun components(path: String): List<String> {
        val result = mutableListOf<String>()
        for (raw in path.split('/', '\\')) {
            if (raw.isEmpty()) continue
            val cleaned = clean(raw)
            if (cleaned.isEmpty() || cleaned == ".") continue
            if (cleaned == "..") throw Failure("traversal")
            result += cleaned
        }
        if (result.isEmpty()) throw Failure("empty")
        if (result.size > MAX_COMPONENTS) throw Failure("too deep")
        return result
    }

    internal fun clean(component: String): String {
        val out = StringBuilder()
        var i = 0
        while (i < component.length) {
            val cp = component.codePointAt(i)
            i += Character.charCount(cp)
            val type = Character.getType(cp)
            if (type == Character.CONTROL.toInt() || type == Character.FORMAT.toInt()) continue
            if (cp == ':'.code) out.append('_') else out.appendCodePoint(cp)
        }
        var text = out.toString().trim(' ')
        if (text.isEmpty() || text == "." || text == "..") return text
        if (text.startsWith(".")) text = "_" + text.substring(1)
        return truncate(text)
    }

    private fun truncate(text: String): String {
        if (text.utf8Size() <= MAX_COMPONENT_BYTES) return text
        var stem = text
        var ext = ""
        val dot = text.lastIndexOf('.')
        if (dot > 0) {
            val candidate = text.substring(dot)
            if (candidate.utf8Size() - 1 <= MAX_EXTENSION_BYTES) {
                ext = candidate
                stem = text.substring(0, dot)
            }
        }
        return stem.truncatedToUtf8Bytes(MAX_COMPONENT_BYTES - ext.utf8Size()) + ext
    }

    /** `name`, or `name (2)`, `name (3)`… — the first one for which [exists] is false. */
    fun uniqueName(name: String, exists: (String) -> Boolean): String {
        if (!exists(name)) return name
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var n = 2
        while (exists("$stem ($n)$ext")) n++
        return "$stem ($n)$ext"
    }
}
