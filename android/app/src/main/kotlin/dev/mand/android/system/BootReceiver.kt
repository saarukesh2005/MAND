package dev.mand.android.system

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dev.mand.android.data.PairedMacStore
import dev.mand.android.service.BridgeService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** Reconnects to the paired Mac after the phone restarts or M’AND is updated. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val pending = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                if (PairedMacStore(context).current() != null) {
                    runCatching { BridgeService.start(context) }
                }
            } finally {
                pending.finish()
            }
        }
    }
}
