package dev.mand.android.tap

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings

/**
 * The simplest path to switching Tap to Send on, worked out on Android 17:
 * an app installed from a file can't turn on an Accessibility service until "Allow restricted settings"
 * is enabled, and Android only shows that option (App info → ⋮) after the person has tried once and seen
 * "App was denied access". So the steps are: try → allow → turn on. Each step opens the exact screen.
 */
object TapSetup {
    enum class Step { TRY_ONCE, ALLOW_RESTRICTED, TURN_ON, DONE }

    private const val PREFS = "tap_setup"
    private const val KEY_TRIED = "tried"
    private const val KEY_ALLOWED = "allowed_restricted"

    /** Which step to show now. [tried]/[allowed] come from what the person already did in earlier steps. */
    fun step(context: Context): Step {
        if (TapService.isEnabled(context)) return Step.DONE
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return when {
            !prefs.getBoolean(KEY_TRIED, false) -> Step.TRY_ONCE
            !prefs.getBoolean(KEY_ALLOWED, false) -> Step.ALLOW_RESTRICTED
            else -> Step.TURN_ON
        }
    }

    /** Skip straight to "turn on" (e.g. installed from a store, so nothing is restricted). */
    fun markAllowed(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_TRIED, true).putBoolean(KEY_ALLOWED, true).apply()
    }

    fun markTried(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_TRIED, true).apply()
    }

    /** Back to the first step (from "Start again" if something went wrong). */
    fun reset(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    /**
     * Opens the Accessibility list with M’AND's entry highlighted. (The direct "details" link jumps to App info on
     * Android 17 for apps installed from a file, which skips the "denied" message that unlocks the permission.)
     */
    fun openServicePage(context: Context) {
        val component = ComponentName(context, TapService::class.java).flattenToString()
        context.startActivity(
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                .putExtra(":settings:fragment_args_key", component)
                .putExtra(":settings:show_fragment_args", Bundle().apply { putString(":settings:fragment_args_key", component) })
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
        )
    }

    /** Opens M’AND's App info page, where ⋮ → Allow restricted settings lives. */
    fun openAppInfo(context: Context) {
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
        )
    }

    /** Whether this copy was installed from a file (then Android restricts Accessibility); store installs aren't. */
    fun isSideloaded(context: Context): Boolean = runCatching {
        val source = context.packageManager.getInstallSourceInfo(context.packageName)
        val store = source.installingPackageName
        store == null || store in setOf("com.google.android.packageinstaller", "com.android.packageinstaller",
            "com.android.shell", "com.google.android.apps.nbu.files")
    }.getOrDefault(true)
}
