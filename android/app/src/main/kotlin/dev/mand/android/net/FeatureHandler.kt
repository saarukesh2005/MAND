package dev.mand.android.net

import dev.mand.core.Message

/** A feature module (files, clipboard, notifications, battery) plugged into [BridgeClient]. */
interface FeatureHandler {
    /** A Mac became connected; [macFeatures] says which optional features it supports. */
    fun onConnected(macFeatures: Set<String>) {}

    fun onDisconnected() {}

    /** A feature message from the Mac. Called on a background thread; must not block for long. */
    fun onMessage(message: Message) {}
}
