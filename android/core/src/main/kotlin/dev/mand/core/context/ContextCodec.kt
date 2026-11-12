package dev.mand.core.context

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Strict JSON (de)serialisation of context events; mirrors ContextCodec.swift. */
object ContextCodec {
    class Failure(reason: String) : Exception(reason)

    private val ID = Regex("^[A-Za-z0-9_-]{1,64}$")
    private val SHA = Regex("^[0-9a-f]{64}$")

    fun encode(events: List<ContextEvent>): String = JsonArray(events.map(::toJson)).toString()

    fun decode(text: String): List<ContextEvent> {
        val list = runCatching { Json.parseToJsonElement(text) }.getOrNull() as? JsonArray ?: fail("not a list")
        return list.map { event(it as? JsonObject ?: fail("event is not an object")) }
    }

    fun toJson(e: ContextEvent): JsonObject = buildJsonObject {
        put("id", e.id)
        put("origin", e.origin)
        put("seq", e.seq)
        put("lamport", e.lamport)
        put("time", e.time)
        put("capsule", e.capsule)
        e.item?.let { put("item", it) }
        put("type", e.body.type)
        put("data", data(e.body))
    }

    private fun data(body: ContextEvent.Body): JsonObject = buildJsonObject {
        when (body) {
            is ContextEvent.Body.CapsuleCreated -> { put("title", body.title); put("description", body.description) }
            is ContextEvent.Body.CapsuleSet -> setFields(body.field.wire, body.value, body.base)
            is ContextEvent.Body.Tagged -> put("tag", body.tag)
            is ContextEvent.Body.Untagged -> put("tag", body.tag)
            is ContextEvent.Body.ItemAdded -> with(body.seed) {
                put("kind", kind.wire); put("title", title); put("text", text); put("url", url)
                put("fileName", fileName); put("sha256", sha256); put("size", size)
            }
            is ContextEvent.Body.ItemSet -> setFields(body.field.wire, body.value, body.base)
            ContextEvent.Body.ItemRemoved, ContextEvent.Body.CapsuleOpened -> Unit
        }
    }

    private fun kotlinx.serialization.json.JsonObjectBuilder.setFields(field: String, value: FieldValue, base: String?) {
        put("field", field)
        when (value) {
            is FieldValue.Str -> put("value", value.value)
            is FieldValue.Num -> put("value", value.value)
            is FieldValue.Flag -> put("value", value.value)
        }
        base?.let { put("base", it) }
    }

    fun event(o: JsonObject): ContextEvent {
        val id = identifier(o["id"], "id")
        val origin = identifier(o["origin"], "origin")
        val capsule = identifier(o["capsule"], "capsule")
        val item = o["item"]?.let { identifier(it, "item") }
        val seq = integer(o["seq"], 1, Long.MAX_VALUE, "seq")
        val lamport = integer(o["lamport"], 1, Long.MAX_VALUE, "lamport")
        val time = integer(o["time"], 0, Long.MAX_VALUE, "time")
        val type = (o["type"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: fail("type")
        val d = o["data"] as? JsonObject ?: fail("data")

        val body: ContextEvent.Body = when (type) {
            "capsule.created" -> ContextEvent.Body.CapsuleCreated(
                text(d["title"], ContextLimits.TITLE_BYTES, true, "title"),
                text(d["description"] ?: JsonPrimitive(""), ContextLimits.DESCRIPTION_BYTES, false, "description"),
            )
            "capsule.set" -> {
                val field = CapsuleField.of(string(d["field"]) ?: "") ?: fail("field")
                ContextEvent.Body.CapsuleSet(field, capsuleValue(field, d["value"]), d["base"]?.let { identifier(it, "base") })
            }
            "capsule.tagged" -> ContextEvent.Body.Tagged(text(d["tag"], ContextLimits.TAG_BYTES, true, "tag"))
            "capsule.untagged" -> ContextEvent.Body.Untagged(text(d["tag"], ContextLimits.TAG_BYTES, true, "tag"))
            "item.added" -> {
                if (item == null) fail("item id")
                val kind = ItemKind.of(string(d["kind"]) ?: "") ?: fail("kind")
                val sha = text(d["sha256"] ?: JsonPrimitive(""), 64, false, "sha256")
                if (sha.isNotEmpty() && !SHA.matches(sha)) fail("sha256")
                ContextEvent.Body.ItemAdded(
                    ItemSeed(
                        kind = kind,
                        title = text(d["title"], ContextLimits.TITLE_BYTES, true, "title"),
                        text = text(d["text"] ?: JsonPrimitive(""), ContextLimits.TEXT_BYTES, false, "text"),
                        url = link(d["url"] ?: JsonPrimitive("")),
                        fileName = text(d["fileName"] ?: JsonPrimitive(""), ContextLimits.FILE_NAME_BYTES, false, "fileName"),
                        sha256 = sha,
                        size = integer(d["size"] ?: JsonPrimitive(0), 0, ContextLimits.MAX_FILE_SIZE, "size"),
                    ),
                )
            }
            "item.set" -> {
                if (item == null) fail("item id")
                val field = ItemField.of(string(d["field"]) ?: "") ?: fail("field")
                ContextEvent.Body.ItemSet(field, itemValue(field, d["value"]), d["base"]?.let { identifier(it, "base") })
            }
            "item.removed" -> if (item == null) fail("item id") else ContextEvent.Body.ItemRemoved
            "capsule.opened" -> ContextEvent.Body.CapsuleOpened
            else -> fail("unknown type $type")
        }
        return ContextEvent(id, origin, seq, lamport, time, capsule, item, body)
    }

    private fun capsuleValue(field: CapsuleField, v: JsonElement?): FieldValue = when (field) {
        CapsuleField.TITLE -> FieldValue.Str(text(v, ContextLimits.TITLE_BYTES, true, "title"))
        CapsuleField.DESCRIPTION -> FieldValue.Str(text(v, ContextLimits.DESCRIPTION_BYTES, false, "description"))
        CapsuleField.PROGRESS -> FieldValue.Num(integer(v, 0, 100, "progress"))
        CapsuleField.PINNED, CapsuleField.ARCHIVED, CapsuleField.DELETED -> FieldValue.Flag(boolean(v, field.wire))
    }

    private fun itemValue(field: ItemField, v: JsonElement?): FieldValue = when (field) {
        ItemField.TITLE -> FieldValue.Str(text(v, ContextLimits.TITLE_BYTES, true, "title"))
        ItemField.TEXT -> FieldValue.Str(text(v, ContextLimits.TEXT_BYTES, false, "text"))
        ItemField.URL -> FieldValue.Str(link(v))
        ItemField.DONE -> FieldValue.Flag(boolean(v, "done"))
    }

    private fun string(v: JsonElement?): String? = (v as? JsonPrimitive)?.takeIf { it.isString }?.content

    private fun identifier(v: JsonElement?, name: String): String = string(v)?.takeIf { ID.matches(it) } ?: fail(name)

    private fun text(v: JsonElement?, max: Int, nonEmpty: Boolean, name: String): String {
        val s = string(v) ?: fail(name)
        if (s.toByteArray(Charsets.UTF_8).size > max || (nonEmpty && s.isEmpty())) fail(name)
        return s
    }

    private fun link(v: JsonElement?): String {
        val s = text(v, ContextLimits.URL_BYTES, false, "url")
        if (s.isEmpty()) return s
        val colon = s.indexOf(':')
        if (colon <= 0 || s.substring(0, colon).lowercase() !in ContextLimits.URL_SCHEMES) fail("url scheme")
        return s
    }

    private fun integer(v: JsonElement?, min: Long, max: Long, name: String): Long {
        val p = v as? JsonPrimitive ?: fail(name)
        if (p.isString) fail(name)
        val c = p.content
        if (c == "true" || c == "false" || c.any { it == '.' || it == 'e' || it == 'E' }) fail(name)
        val n = c.toLongOrNull() ?: fail(name)
        if (n < min || n > max) fail(name)
        return n
    }

    private fun boolean(v: JsonElement?, name: String): Boolean {
        val p = v as? JsonPrimitive ?: fail(name)
        if (p.isString) fail(name)
        return when (p.content) {
            "true" -> true
            "false" -> false
            else -> fail(name)
        }
    }

    private fun fail(reason: String): Nothing = throw Failure(reason)
}
