package com.bellukstudio.multiwhatsappweb.nativewebview

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import android.os.Message
import android.os.Messenger
import android.os.RemoteException
import android.util.Log
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

private const val TAG = "SlotEmbedView"

/**
 * Host-process side of the cross-process embedding. A plain
 * `SurfaceView` living in the MAIN app process (so it's a completely
 * normal, same-process Flutter `AndroidView`) that binds to the
 * appropriate `WebViewSlotServiceN` and, once that remote process
 * reports back a `SurfaceControlViewHost.SurfacePackage`, projects that
 * remote content into itself via `setChildSurfacePackage`.
 *
 * ⚠️ See `WebViewSlotService.kt`'s class doc for the specific API points
 * I'm least certain about without live testing — the risk is
 * concentrated in that file and in `getHostToken()` timing below, not
 * spread evenly through this one.
 */
class SlotEmbedView(
    private val context: Context,
    viewId: Int,
    creationParams: Map<String?, Any?>?,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) : PlatformView {

    private val surfaceView = SurfaceView(context)
    private val channel = MethodChannel(messenger, "multiwhatsappweb/slot_embed_$viewId")

    private val slot = (creationParams?.get("slot") as? Int) ?: 0
    private val accountId = creationParams?.get("accountId") as? String ?: "unknown"
    private val initialUrl =
        creationParams?.get("initialUrl") as? String ?: "https://web.whatsapp.com"

    private var serviceMessenger: Messenger? = null
    private var attachAttempted = false

    private val replyHandler = android.os.Handler(android.os.Looper.getMainLooper()) { msg ->
        when (msg.what) {
            WebViewSlotService.MSG_ATTACHED -> {
                val pkg = msg.data?.getParcelable<android.view.SurfaceControlViewHost.SurfacePackage>(
                    WebViewSlotService.KEY_SURFACE_PACKAGE,
                )
                if (pkg != null) {
                    try {
                        surfaceView.setChildSurfacePackage(pkg)
                        channel.invokeMethod("attached", null)
                    } catch (e: Exception) {
                        Log.e(TAG, "setChildSurfacePackage failed", e)
                        channel.invokeMethod("attachFailed", e.message)
                    }
                } else {
                    Log.e(TAG, "MSG_ATTACHED with null surfacePackage")
                    channel.invokeMethod("attachFailed", "surfacePackage_null")
                }
                true
            }
            WebViewSlotService.MSG_ATTACH_FAILED -> {
                val error = msg.data?.getString(WebViewSlotService.KEY_ERROR)
                Log.e(TAG, "Remote attach failed: $error")
                true
            }
            else -> false
        }
    }
    private val replyMessenger = Messenger(replyHandler)

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            serviceMessenger = Messenger(binder)
            tryAttach()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            serviceMessenger = null
        }
    }

    init {
        surfaceView.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                bindSlotService()
            }

            override fun surfaceChanged(
                holder: SurfaceHolder,
                format: Int,
                width: Int,
                height: Int,
            ) {
                serviceMessenger?.let { m ->
                    val resize = Message.obtain(null, WebViewSlotService.MSG_RESIZE).apply {
                        arg1 = width
                        arg2 = height
                    }
                    try {
                        m.send(resize)
                    } catch (_: RemoteException) {
                    }
                }
                if (!attachAttempted) tryAttach()
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {}
        })
    }

    private fun bindSlotService() {
        val serviceClass = slotServiceClasses.getOrNull(slot) ?: run {
            Log.e(TAG, "Invalid slot index: $slot")
            return
        }
        val intent = Intent().apply {
            component = ComponentName(context, serviceClass)
        }
        // startService (in addition to bindService below) is what keeps
        // the slot's WebView alive across account switches — see
        // WebViewSlotService.onStartCommand's doc. Without this, the
        // service (and its WebView) could be torn down as soon as we
        // unbind (switching away), forcing a full reload every time you
        // switch back.
        context.startService(intent)
        context.bindService(intent, connection, Context.BIND_AUTO_CREATE)
    }

    private fun tryAttach() {
        // ⚠️ TIMING RISK: getHostToken() requires the SurfaceView to be
        // attached to a window AND to have a live surface — this is
        // called from both surfaceCreated and surfaceChanged specifically
        // because I'm not fully certain which callback reliably fires
        // AFTER the host token becomes available on every device/API
        // level combination. If `hostToken` comes back null here, that's
        // the first thing to add logging around.
        if (attachAttempted) return
        val messengerRef = serviceMessenger ?: return
        val hostToken = surfaceView.hostToken ?: return
        val width = surfaceView.width
        val height = surfaceView.height
        if (width <= 0 || height <= 0) return

        attachAttempted = true

        val displayId = surfaceView.display?.displayId ?: 0

        val data = Bundle().apply {
            putBinder(WebViewSlotService.KEY_HOST_TOKEN, hostToken)
            putInt(WebViewSlotService.KEY_DISPLAY_ID, displayId)
            putInt(WebViewSlotService.KEY_WIDTH, width)
            putInt(WebViewSlotService.KEY_HEIGHT, height)
            putString(WebViewSlotService.KEY_ACCOUNT_ID, accountId)
            putString(WebViewSlotService.KEY_INITIAL_URL, initialUrl)
        }
        val request = Message.obtain(null, WebViewSlotService.MSG_ATTACH)
        request.setData(data)
        request.replyTo = replyMessenger
        try {
            messengerRef.send(request)
        } catch (e: RemoteException) {
            Log.e(TAG, "Failed to send MSG_ATTACH", e)
        }
    }

    override fun getView(): View = surfaceView

    override fun onFlutterViewAttached(flutterView: View) {}
    override fun onFlutterViewDetached() {}

    override fun dispose() {
        channel.setMethodCallHandler(null)
        // FIX (always reloads on account switch): previously sent
        // MSG_RELEASE here, which destroyed the remote WebView entirely
        // every time you switched away from an account — even though
        // that account's process/slot binding was going to stay alive
        // for the rest of the app run regardless (see SlotAllocator
        // doc). Just unbinding (not releasing) lets the WebView keep
        // running/rendering in the background, so switching back
        // reattaches to the SAME already-loaded page instead of
        // reloading from scratch. See WebViewSlotService's
        // onStartCommand/handleAttach for the other half of this fix.
        try {
            context.unbindService(connection)
        } catch (_: IllegalArgumentException) {
            // Wasn't bound — fine, nothing to clean up.
        }
    }

    companion object {
        val slotServiceClasses = listOf(
            WebViewSlotService0::class.java,
            WebViewSlotService1::class.java,
            WebViewSlotService2::class.java,
            WebViewSlotService3::class.java,
            WebViewSlotService4::class.java,
            WebViewSlotService5::class.java,
        )
    }
}

class SlotEmbedViewFactory(
    private val messenger: io.flutter.plugin.common.BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val creationParams = args as? Map<String?, Any?>
        return SlotEmbedView(context, viewId, creationParams, messenger)
    }
}