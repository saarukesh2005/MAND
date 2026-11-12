package dev.mand.core.context

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/** Runs protocol/vectors/context-v1.json — the same cases the Swift MandContext tests run. */
class ContextVectorTest {
    private val root = Json.parseToJsonElement(File(System.getProperty("mand.contextVectors")).readText()).jsonObject
    private fun cases(key: String) = root[key]!!.jsonArray.map { it.jsonObject }

    /** Numbers compare by value (JSON 40 == 40L), everything else structurally. */
    private fun normalize(e: JsonElement): JsonElement = when (e) {
        is JsonObject -> JsonObject(e.mapValues { normalize(it.value) })
        is JsonArray -> JsonArray(e.map(::normalize))
        is JsonPrimitive -> if (!e.isString && e.longOrNull != null) JsonPrimitive(e.longOrNull) else e
        else -> e
    }

    @Test
    fun fold() {
        for (case in cases("fold")) {
            val name = case["name"]!!.jsonPrimitive.content
            val events = case["events"]!!.jsonArray.map { ContextCodec.event(it.jsonObject) }
            val asOf = case["asOf"]?.jsonPrimitive?.longOrNull
            val expected = normalize(case["expect"]!!)
            assertEquals(expected, normalize(ContextSummary.of(CapsuleReducer.fold(events, asOf))), name)
            assertEquals(expected, normalize(ContextSummary.of(CapsuleReducer.fold(events.reversed(), asOf))), "$name (reversed)")
        }
    }

    @Test
    fun invalid() {
        for (case in cases("invalid")) {
            assertFailsWith<ContextCodec.Failure>(case["name"]!!.jsonPrimitive.content) { ContextCodec.event(case["event"]!!.jsonObject) }
        }
    }

    @Test
    fun valid() {
        for (case in cases("valid")) {
            val event = ContextCodec.event(case["event"]!!.jsonObject)
            assertEquals(listOf(event), ContextCodec.decode(ContextCodec.encode(listOf(event))), case["name"]!!.jsonPrimitive.content)
        }
    }

    @Test
    fun `time machine restores a removed item by appending events`() {
        val a = ContextAuthor("pixel")
        val events = mutableListOf(
            a.make("c", ContextEvent.Body.CapsuleCreated("Taxation", ""), time = 1_000),
            a.make("c", ContextEvent.Body.ItemAdded(ItemSeed(ItemKind.ACTION, "Perquisites")), item = "x", time = 2_000),
        )
        events += a.make("c", ContextEvent.Body.ItemSet(ItemField.DONE, FieldValue.Flag(true), null), item = "x", time = 2_500)
        events += a.make("c", ContextEvent.Body.ItemRemoved, item = "x", time = 3_000)
        val now = CapsuleReducer.fold(events)
        val past = CapsuleReducer.fold(events, asOf = 2_600).capsules.getValue("c")
        val changes = TimeMachine.diff(now.capsules.getValue("c"), past)
        for ((item, body) in TimeMachine.restore(changes, "c", now)) events += a.make("c", body, item, time = 4_000)
        val restored = CapsuleReducer.fold(events).capsules.getValue("c")
        assertEquals(listOf("Perquisites"), restored.items.map { it.title })
        assertTrue(restored.items.single().done)
        assertTrue(CapsuleReducer.fold(events).conflicts.isEmpty())
    }
}
