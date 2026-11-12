package dev.mand.core.context

import java.util.UUID

/**
 * One immutable entry in the context log (TECHNICAL_DECISIONS D22). Mirrors
 * mac/Sources/MandContext/ContextEvent.swift; both are checked against protocol/vectors/context-v1.json.
 */
data class ContextEvent(
    val id: String,
    val origin: String,
    val seq: Long,
    val lamport: Long,
    val time: Long,
    val capsule: String,
    val item: String? = null,
    val body: Body,
) {
    sealed interface Body {
        val type: String

        data class CapsuleCreated(val title: String, val description: String) : Body {
            override val type get() = "capsule.created"
        }
        data class CapsuleSet(val field: CapsuleField, val value: FieldValue, val base: String?) : Body {
            override val type get() = "capsule.set"
        }
        data class Tagged(val tag: String) : Body {
            override val type get() = "capsule.tagged"
        }
        data class Untagged(val tag: String) : Body {
            override val type get() = "capsule.untagged"
        }
        data class ItemAdded(val seed: ItemSeed) : Body {
            override val type get() = "item.added"
        }
        data class ItemSet(val field: ItemField, val value: FieldValue, val base: String?) : Body {
            override val type get() = "item.set"
        }
        data object ItemRemoved : Body {
            override val type get() = "item.removed"
        }
        data object CapsuleOpened : Body {
            override val type get() = "capsule.opened"
        }
    }

    companion object {
        /** Total order used by every device: (lamport, origin, seq, id). */
        val ORDER: Comparator<ContextEvent> =
            compareBy<ContextEvent> { it.lamport }.thenBy { it.origin }.thenBy { it.seq }.thenBy { it.id }
    }
}

enum class CapsuleField(val wire: String) {
    TITLE("title"), DESCRIPTION("description"), PROGRESS("progress"), PINNED("pinned"), ARCHIVED("archived"), DELETED("deleted");

    companion object {
        fun of(wire: String) = entries.firstOrNull { it.wire == wire }
    }
}

enum class ItemField(val wire: String) {
    TITLE("title"), TEXT("text"), URL("url"), DONE("done");

    companion object {
        fun of(wire: String) = entries.firstOrNull { it.wire == wire }
    }
}

enum class ItemKind(val wire: String) {
    FILE("file"), URL("url"), NOTE("note"), SCREENSHOT("screenshot"), ACTION("action");

    companion object {
        fun of(wire: String) = entries.firstOrNull { it.wire == wire }
    }
}

sealed interface FieldValue {
    data class Str(val value: String) : FieldValue
    data class Num(val value: Long) : FieldValue
    data class Flag(val value: Boolean) : FieldValue
}

data class ItemSeed(
    val kind: ItemKind,
    val title: String,
    val text: String = "",
    val url: String = "",
    val fileName: String = "",
    val sha256: String = "",
    val size: Long = 0,
)

/** Validation limits shared with Swift (ContextLimits). */
object ContextLimits {
    const val ID_BYTES = 64
    const val TITLE_BYTES = 256
    const val DESCRIPTION_BYTES = 4_096
    const val TEXT_BYTES = 65_536
    const val URL_BYTES = 2_048
    const val TAG_BYTES = 64
    const val FILE_NAME_BYTES = 255
    const val MAX_FILE_SIZE = 1L shl 40
    val URL_SCHEMES = setOf("http", "https", "mailto", "tel")
}

/** Creates correctly ordered events for this device (per-device seq, Lamport clock). */
class ContextAuthor(val origin: String, seq: Long = 0, lamport: Long = 0) {
    var seq = seq
        private set
    var lamport = lamport
        private set

    fun observe(events: Iterable<ContextEvent>) {
        for (e in events) {
            lamport = maxOf(lamport, e.lamport)
            if (e.origin == origin) seq = maxOf(seq, e.seq)
        }
    }

    fun make(capsule: String, body: ContextEvent.Body, item: String? = null, time: Long = System.currentTimeMillis()): ContextEvent {
        seq += 1
        lamport += 1
        return ContextEvent(newId(), origin, seq, lamport, time, capsule, item, body)
    }

    companion object {
        fun newId(): String = UUID.randomUUID().toString().replace("-", "")
    }
}
