package dev.mand.android.clipboard

import android.app.PendingIntent
import android.content.Intent
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import dev.mand.android.MandApp
import dev.mand.android.net.LinkState

/** Quick Settings tile: “Send clipboard to Mac”. */
class ClipboardTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        val app = application as MandApp
        val ready = app.settings.prefs.value.clipboardEnabled && app.client.state.value is LinkState.Connected
        qsTile?.apply {
            state = if (ready) Tile.STATE_INACTIVE else Tile.STATE_UNAVAILABLE
            subtitle = if (ready) "To Mac" else "Not connected"
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val intent = Intent(this, ClipboardSendActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE))
    }
}
