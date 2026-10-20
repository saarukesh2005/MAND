package dev.mand.android.system

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

/**
 * Android 17 (API 37) blocks local-network traffic unless the user grants ACCESS_LOCAL_NETWORK
 * ("Nearby devices"). Earlier versions allow it with INTERNET and must NOT request it.
 */
object LocalNetworkAccess {
    // String literal: the constant only exists on API 37, but the string is safe to use everywhere.
    const val PERMISSION = "android.permission.ACCESS_LOCAL_NETWORK"
    private const val API_LOCAL_NETWORK = 37

    val isRequired: Boolean get() = Build.VERSION.SDK_INT >= API_LOCAL_NETWORK

    fun isGranted(context: Context): Boolean =
        !isRequired || context.checkSelfPermission(PERMISSION) == PackageManager.PERMISSION_GRANTED
}
