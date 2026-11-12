package dev.mand.core.context

/** A Task Capsule as currently known (derived from the log). Mirrors Capsule in CapsuleReducer.swift. */
data class Capsule(
    val id: String,
    val title: String,
    val description: String,
    val tags: Set<String> = emptySet(),
    val pinned: Boolean = false,
    val archived: Boolean = false,
    val deleted: Boolean = false,
    val progress: Long = 0,
    val createdAt: Long,
    val createdOn: String,
    val updatedAt: Long,
    val lastActive: Long,
    val lastDevice: String,
    val devices: Map<String, Long> = emptyMap(),
    val items: List<CapsuleItem> = emptyList(),
) {
    val pendingActions get() = items.filter { it.kind == ItemKind.ACTION && !it.done }
    val completedActions get() = items.filter { it.kind == ItemKind.ACTION && it.done }
}

data class CapsuleItem(
    val id: String,
    val kind: ItemKind,
    val title: String,
    val text: String,
    val url: String,
    val fileName: String,
    val sha256: String,
    val size: Long,
    val done: Boolean = false,
    val addedAt: Long,
    val addedOn: String,
)

data class ContextConflict(
    val capsule: String,
    val item: String?,
    val field: String,
    val kept: FieldValue,
    val keptEvent: String,
    val lost: FieldValue,
    val lostEvent: String,
)

data class ContextState(
    val capsules: Map<String, Capsule> = emptyMap(),
    val conflicts: List<ContextConflict> = emptyList(),
    val lastWriter: Map<String, String> = emptyMap(),
) {
    /** Visible capsules: not deleted, pinned first, then most recently active. */
    val visible: List<Capsule>
        get() = capsules.values.filterNot { it.deleted }
            .sortedWith(compareByDescending<Capsule> { it.pinned }.thenByDescending { it.lastActive }.thenBy { it.id })

    companion object {
        fun key(capsule: String, item: String?, field: String) = "$capsule/${item ?: ""}/$field"
    }
}

/** Deterministic fold of the context log; mirrors CapsuleReducer.swift exactly. */
object CapsuleReducer {
    fun fold(events: Iterable<ContextEvent>, asOf: Long? = null): ContextState {
        val ordered = events.distinctBy { it.id }.sortedWith(ContextEvent.ORDER)
        val capsules = LinkedHashMap<String, Capsule>()
        val conflicts = mutableListOf<ContextConflict>()
        val writers = HashMap<String, String>()
        for (e in ordered) {
            if (asOf != null && e.time > asOf) continue
            apply(e, capsules, conflicts, writers)
        }
        return ContextState(capsules, conflicts, writers)
    }

    private fun apply(
        e: ContextEvent,
        capsules: MutableMap<String, Capsule>,
        conflicts: MutableList<ContextConflict>,
        writers: MutableMap<String, String>,
    ) {
        val body = e.body
        if (body is ContextEvent.Body.CapsuleCreated) {
            if (capsules.containsKey(e.capsule)) return
            capsules[e.capsule] = Capsule(
                id = e.capsule, title = body.title, description = body.description, createdAt = e.time,
                createdOn = e.origin, updatedAt = e.time, lastActive = e.time, lastDevice = e.origin,
                devices = mapOf(e.origin to e.time),
            )
            writers[ContextState.key(e.capsule, null, "title")] = e.id
            writers[ContextState.key(e.capsule, null, "description")] = e.id
            return
        }
        var c = capsules[e.capsule] ?: return
        c = c.copy(devices = c.devices + (e.origin to maxOf(c.devices[e.origin] ?: 0, e.time)))
        val touched = maxOf(c.updatedAt, e.time)
        c = when (body) {
            is ContextEvent.Body.CapsuleSet -> {
                record(e, null, body.field.wire, body.value, value(c, body.field), body.base, conflicts, writers)
                set(c, body.field, body.value).copy(updatedAt = touched)
            }
            is ContextEvent.Body.Tagged -> c.copy(tags = c.tags + body.tag, updatedAt = touched)
            is ContextEvent.Body.Untagged -> c.copy(tags = c.tags - body.tag, updatedAt = touched)
            is ContextEvent.Body.ItemAdded -> {
                val id = e.item
                if (id == null || c.items.any { it.id == id }) {
                    c
                } else {
                    val s = body.seed
                    for (f in listOf("title", "text", "url", "done")) writers[ContextState.key(e.capsule, id, f)] = e.id
                    c.copy(
                        items = c.items + CapsuleItem(id, s.kind, s.title, s.text, s.url, s.fileName, s.sha256, s.size,
                            addedAt = e.time, addedOn = e.origin),
                        updatedAt = touched,
                    )
                }
            }
            is ContextEvent.Body.ItemSet -> {
                val index = c.items.indexOfFirst { it.id == e.item }
                if (index < 0) {
                    c
                } else {
                    val old = c.items[index]
                    record(e, e.item, body.field.wire, body.value, value(old, body.field), body.base, conflicts, writers)
                    c.copy(items = c.items.toMutableList().also { it[index] = set(old, body.field, body.value) }, updatedAt = touched)
                }
            }
            ContextEvent.Body.ItemRemoved -> c.copy(items = c.items.filterNot { it.id == e.item }, updatedAt = touched)
            ContextEvent.Body.CapsuleOpened ->
                if (e.time >= c.lastActive) c.copy(lastActive = e.time, lastDevice = e.origin) else c
            is ContextEvent.Body.CapsuleCreated -> c
        }
        capsules[e.capsule] = c
    }

    private fun record(
        e: ContextEvent, item: String?, field: String, new: FieldValue, old: FieldValue, base: String?,
        conflicts: MutableList<ContextConflict>, writers: MutableMap<String, String>,
    ) {
        val key = ContextState.key(e.capsule, item, field)
        val current = writers[key]
        if (base != null && current != null && base != current && old != new) {
            conflicts += ContextConflict(e.capsule, item, field, new, e.id, old, current)
        } else if (base != null && base == current) {
            conflicts.removeAll { it.capsule == e.capsule && it.item == item && it.field == field }
        }
        writers[key] = e.id
    }

    fun value(c: Capsule, f: CapsuleField): FieldValue = when (f) {
        CapsuleField.TITLE -> FieldValue.Str(c.title)
        CapsuleField.DESCRIPTION -> FieldValue.Str(c.description)
        CapsuleField.PROGRESS -> FieldValue.Num(c.progress)
        CapsuleField.PINNED -> FieldValue.Flag(c.pinned)
        CapsuleField.ARCHIVED -> FieldValue.Flag(c.archived)
        CapsuleField.DELETED -> FieldValue.Flag(c.deleted)
    }

    fun value(i: CapsuleItem, f: ItemField): FieldValue = when (f) {
        ItemField.TITLE -> FieldValue.Str(i.title)
        ItemField.TEXT -> FieldValue.Str(i.text)
        ItemField.URL -> FieldValue.Str(i.url)
        ItemField.DONE -> FieldValue.Flag(i.done)
    }

    private fun set(c: Capsule, f: CapsuleField, v: FieldValue): Capsule = when {
        f == CapsuleField.TITLE && v is FieldValue.Str -> c.copy(title = v.value)
        f == CapsuleField.DESCRIPTION && v is FieldValue.Str -> c.copy(description = v.value)
        f == CapsuleField.PROGRESS && v is FieldValue.Num -> c.copy(progress = v.value)
        f == CapsuleField.PINNED && v is FieldValue.Flag -> c.copy(pinned = v.value)
        f == CapsuleField.ARCHIVED && v is FieldValue.Flag -> c.copy(archived = v.value)
        f == CapsuleField.DELETED && v is FieldValue.Flag -> c.copy(deleted = v.value)
        else -> c
    }

    private fun set(i: CapsuleItem, f: ItemField, v: FieldValue): CapsuleItem = when {
        f == ItemField.TITLE && v is FieldValue.Str -> i.copy(title = v.value)
        f == ItemField.TEXT && v is FieldValue.Str -> i.copy(text = v.value)
        f == ItemField.URL && v is FieldValue.Str -> i.copy(url = v.value)
        f == ItemField.DONE && v is FieldValue.Flag -> i.copy(done = v.value)
        else -> i
    }
}

/** Change between two versions of a capsule (Time Machine), mirrors CapsuleChange in Swift. */
sealed interface CapsuleChange {
    data class Field(val field: CapsuleField, val from: FieldValue, val to: FieldValue) : CapsuleChange
    data class TagAdded(val tag: String) : CapsuleChange
    data class TagRemoved(val tag: String) : CapsuleChange
    data class ItemAddedChange(val item: CapsuleItem) : CapsuleChange
    data class ItemRemovedChange(val item: CapsuleItem) : CapsuleChange
    data class ItemChanged(val id: String, val title: String, val field: ItemField, val from: FieldValue, val to: FieldValue) : CapsuleChange
}

object TimeMachine {
    fun diff(old: Capsule, new: Capsule): List<CapsuleChange> = buildList {
        for (f in CapsuleField.entries) {
            val a = CapsuleReducer.value(old, f)
            val b = CapsuleReducer.value(new, f)
            if (a != b) add(CapsuleChange.Field(f, a, b))
        }
        (new.tags - old.tags).sorted().forEach { add(CapsuleChange.TagAdded(it)) }
        (old.tags - new.tags).sorted().forEach { add(CapsuleChange.TagRemoved(it)) }
        val oldItems = old.items.associateBy { it.id }
        val newItems = new.items.associateBy { it.id }
        new.items.filter { it.id !in oldItems }.forEach { add(CapsuleChange.ItemAddedChange(it)) }
        old.items.filter { it.id !in newItems }.forEach { add(CapsuleChange.ItemRemovedChange(it)) }
        for (item in new.items) {
            val before = oldItems[item.id] ?: continue
            for (f in ItemField.entries) {
                val a = CapsuleReducer.value(before, f)
                val b = CapsuleReducer.value(item, f)
                if (a != b) add(CapsuleChange.ItemChanged(item.id, item.title, f, a, b))
            }
        }
    }

    /** Bodies (with item ids) that apply `changes`, each naming the current writer as base. */
    fun restore(changes: List<CapsuleChange>, capsule: String, state: ContextState): List<Pair<String?, ContextEvent.Body>> =
        changes.flatMap { change ->
            when (change) {
                is CapsuleChange.Field -> listOf(
                    null to ContextEvent.Body.CapsuleSet(change.field, change.to, state.lastWriter[ContextState.key(capsule, null, change.field.wire)]),
                )
                is CapsuleChange.TagAdded -> listOf(null to ContextEvent.Body.Tagged(change.tag))
                is CapsuleChange.TagRemoved -> listOf(null to ContextEvent.Body.Untagged(change.tag))
                is CapsuleChange.ItemAddedChange -> with(change.item) {
                    listOfNotNull(
                        id to ContextEvent.Body.ItemAdded(ItemSeed(kind, title, text, url, fileName, sha256, size)),
                        if (done) id to ContextEvent.Body.ItemSet(ItemField.DONE, FieldValue.Flag(true), null) else null,
                    )
                }
                is CapsuleChange.ItemRemovedChange -> listOf(change.item.id to ContextEvent.Body.ItemRemoved)
                is CapsuleChange.ItemChanged -> listOf(
                    change.id to ContextEvent.Body.ItemSet(change.field, change.to, state.lastWriter[ContextState.key(capsule, change.id, change.field.wire)]),
                )
            }
        }

    fun timeline(events: Iterable<ContextEvent>, capsule: String? = null): List<ContextEvent> =
        events.filter { capsule == null || it.capsule == capsule }.sortedWith(ContextEvent.ORDER.reversed())
}

/** Canonical view for the shared vectors (same keys as ContextSummary.swift). */
object ContextSummary {
    fun of(state: ContextState): kotlinx.serialization.json.JsonObject = kotlinx.serialization.json.buildJsonObject {
        put("capsules", kotlinx.serialization.json.JsonArray(state.capsules.values.sortedBy { it.id }.map { c ->
            kotlinx.serialization.json.buildJsonObject {
                put("id", kotlinx.serialization.json.JsonPrimitive(c.id))
                put("title", kotlinx.serialization.json.JsonPrimitive(c.title))
                put("description", kotlinx.serialization.json.JsonPrimitive(c.description))
                put("tags", kotlinx.serialization.json.JsonArray(c.tags.sorted().map { kotlinx.serialization.json.JsonPrimitive(it) }))
                put("pinned", kotlinx.serialization.json.JsonPrimitive(c.pinned))
                put("archived", kotlinx.serialization.json.JsonPrimitive(c.archived))
                put("deleted", kotlinx.serialization.json.JsonPrimitive(c.deleted))
                put("progress", kotlinx.serialization.json.JsonPrimitive(c.progress))
                put("lastDevice", kotlinx.serialization.json.JsonPrimitive(c.lastDevice))
                put("devices", kotlinx.serialization.json.JsonArray(c.devices.keys.sorted().map { kotlinx.serialization.json.JsonPrimitive(it) }))
                put("items", kotlinx.serialization.json.JsonArray(c.items.map { i ->
                    kotlinx.serialization.json.buildJsonObject {
                        put("id", kotlinx.serialization.json.JsonPrimitive(i.id))
                        put("kind", kotlinx.serialization.json.JsonPrimitive(i.kind.wire))
                        put("title", kotlinx.serialization.json.JsonPrimitive(i.title))
                        put("text", kotlinx.serialization.json.JsonPrimitive(i.text))
                        put("url", kotlinx.serialization.json.JsonPrimitive(i.url))
                        put("done", kotlinx.serialization.json.JsonPrimitive(i.done))
                    }
                }))
            }
        }))
        put("conflicts", kotlinx.serialization.json.JsonArray(state.conflicts.map { c ->
            kotlinx.serialization.json.buildJsonObject {
                put("capsule", kotlinx.serialization.json.JsonPrimitive(c.capsule))
                put("item", kotlinx.serialization.json.JsonPrimitive(c.item ?: ""))
                put("field", kotlinx.serialization.json.JsonPrimitive(c.field))
                put("kept", kotlinx.serialization.json.JsonPrimitive(c.keptEvent))
                put("lost", kotlinx.serialization.json.JsonPrimitive(c.lostEvent))
            }
        }))
    }
}
