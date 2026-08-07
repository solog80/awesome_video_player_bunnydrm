package uz.shs.better_player_plus

import android.content.Context
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Creates a native media3 [PlayerView] PlatformView that the ExoPlayer renders into.
 *
 * L1 secure Widevine frames can ONLY be displayed on a native SurfaceView that is
 * managed by ExoPlayer (a PlayerView uses a SurfaceView internally and handles the
 * secure surface correctly — Flutter textures show a green screen for L1).
 *
 * This mirrors the native ExoPlayer test that renders L1 correctly.
 */
class NativeSurfaceViewFactory(
    private val plugin: BetterPlayerPlugin
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val rawId = (args as? Map<*, *>)?.get("textureId")
        val textureId = (rawId as? Number)?.toLong() ?: 0L

        val playerView = PlayerView(context).apply {
            useController = false
            player = plugin.getExoPlayer(textureId)
        }

        return object : PlatformView {
            override fun getView(): PlayerView = playerView

            override fun dispose() {
                playerView.player = null
                plugin.detachSurface(textureId)
            }
        }
    }
}
