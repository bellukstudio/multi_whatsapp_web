package com.bellukstudio.multi_whatsapp_web.nativewebview

import android.app.Service
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.view.SurfaceControlViewHost
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout

/**
 * Runs in its own dedicated OS process (see AndroidManifest.xml —
 * `android:process=":webview_slot_N"` on each of the N declared
 * services). Hosts a real WebView via `SurfaceControlViewHost` so its
 * pixels can be projected into a `SurfaceView` living in the MAIN app
 * process's Flutter view tree (see `SlotEmbedView.kt`), instead of
 * showing as a separate full-screen Activity.
 *
 * ⚠️ HIGH-RISK / UNVERIFIED (read before debugging): this whole
 * approach (`SurfaceControlViewHost` cross-process view embedding,
 * Android 11+/API 30+) is something I could not compile or run against
 * a real device to confirm. The parts most likely to need adjustment if
 * this doesn't work as-is:
 *   1. `SurfaceControlViewHost(this, display, hostToken)` constructor —
 *      confirm this 3-arg overload exists on your compileSdk; some docs
 *      show an overload taking a `SurfaceControlViewHost.HostToken`
 *      wrapper instead of a raw `IBinder` on newer API levels.
 *   2. Obtaining `hostToken` on the CALLING (host/Flutter) side via
 *      `SurfaceView.getHostToken()` — this requires the SurfaceView to
 *      already be attached to a window; timing matters (see
 *      `SlotEmbedView.kt`'s comment on this).
 *   3. Whether `attachedToWindow`/input-focus forwarding "just works"
 *      for a WebView (which needs keyboard input for the QR-login flow
 *      or typing) inside a `SurfaceControlViewHost` the way it does for
 *      simpler content — WebView + soft keyboard + cross-process
 *      embedding is a combination I have low confidence in without
 *      testing.
 * If any of these throw or silently fail to render, send me the exact
 * Logcat stack trace (search for "FATAL EXCEPTION" or the service's own
 * tag) rather than just "doesn't work" — the fix is almost certainly a
 * small adjustment to one of these three points, not a rewrite.
 */
open class WebViewSlotService : Service() {

    private var webView: WebView? = null
    private var viewHost: SurfaceControlViewHost? = null
    private var suffixApplied = false

    private val incomingHandler = Handler(Looper.getMainLooper()) { msg ->
        when (msg.what) {
            MSG_ATTACH -> {
                handleAttach(msg)
                true
            }
            MSG_RESIZE -> {
                val width = msg.arg1
                val height = msg.arg2
                viewHost?.relayout(width, height)
                true
            }
            MSG_RELEASE -> {
                release()
                true
            }
            else -> false
        }
    }
    private val messenger = Messenger(incomingHandler)

    override fun onBind(intent: Intent?): IBinder = messenger.binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // FIX (always reloads on account switch): keeps this service
        // (and whatever WebView it's holding) alive even while nothing
        // is currently bound to it — e.g. between switching away from
        // this account and switching back. Without this, Android is
        // free to tear the service down as soon as the last binder
        // unbinds (see SlotEmbedView.kt's dispose(), which
        // intentionally only unbinds now instead of sending
        // MSG_RELEASE), which would silently destroy the WebView anyway
        // and defeat the whole point of this fix.
        return START_STICKY
    }

    private fun handleAttach(msg: Message) {
        val data = msg.data ?: return
        val replyTo = msg.replyTo
        val hostToken = data.getBinder(KEY_HOST_TOKEN) ?: return
        val displayId = data.getInt(KEY_DISPLAY_ID)
        val width = data.getInt(KEY_WIDTH)
        val height = data.getInt(KEY_HEIGHT)
        val accountId = data.getString(KEY_ACCOUNT_ID) ?: "unknown"
        val initialUrl = data.getString(KEY_INITIAL_URL) ?: "https://web.whatsapp.com"

        if (!suffixApplied) {
            try {
                WebView.setDataDirectorySuffix(accountId)
                suffixApplied = true
            } catch (_: IllegalStateException) {
                // Shouldn't happen — this process only ever handles one
                // MSG_ATTACH for its whole lifetime (one slot = one
                // account). Fail safe rather than crash if it somehow
                // does.
            }
        }

        val displayManager = getSystemService(DisplayManager::class.java)
        val display = displayManager.getDisplay(displayId) ?: run {
            replyTo?.let { replyErrorTo(it, "display_not_found") }
            return
        }

        // FIX (always reloads on every account switch): previously this
        // ALWAYS created a brand-new WebView + called loadUrl() on every
        // attach, even when re-attaching to an account whose process
        // (and WebView) never actually stopped running in the
        // background — the OLD SurfaceControlViewHost (tied to the
        // PREVIOUS host Activity's/AndroidView's window) was simply
        // released when you switched away, but the WebView itself
        // doesn't need to die just because its visual attachment did.
        // Now: only create a fresh WebView (and navigate) the FIRST time
        // this slot/process is ever attached. On every subsequent
        // attach (switching back to this account), reuse the EXISTING
        // WebView/container as-is — same page, same scroll position, no
        // reload — and just wrap it in a NEW SurfaceControlViewHost
        // pointed at the new host token.
        val existingWebView = webView
        val container: FrameLayout
        if (existingWebView != null) {
            container = existingWebView.parent as? FrameLayout
                ?: FrameLayout(this).also { it.addView(existingWebView) }
        } else {
            val wv = WebView(this).also { webView = it }
            val settings: WebSettings = wv.settings
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            settings.mediaPlaybackRequiresUserGesture = true
            settings.setSupportZoom(false)

            var replySent = false
            wv.webViewClient = object : WebViewClient() {
                override fun onPageCommitVisible(view: WebView?, url: String?) {
                    super.onPageCommitVisible(view, url)
                    if (!replySent) {
                        replySent = true
                        sendSurfacePackageReply(replyTo)
                    }
                }
            }
            wv.webChromeClient = WebChromeClient()

            container = FrameLayout(this)
            container.addView(
                wv,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )

            wv.loadUrl(initialUrl)

            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (!replySent) {
                    replySent = true
                    sendSurfacePackageReply(replyTo)
                }
            }, 4000)
        }

        // Tear down the PREVIOUS SurfaceControlViewHost (tied to
        // whichever host attached last time), if any — but this does
        // NOT touch `webView`/`container`, only the visual-attachment
        // plumbing, per the fix above.
        viewHost?.release()
        viewHost = null

        // ⚠️ See class doc point 1 — confirm this constructor overload
        // against your compileSdk if this line doesn't compile/throws.
        val host = SurfaceControlViewHost(this, display, hostToken)
        host.setView(container, width, height)
        viewHost = host

        if (existingWebView != null) {
            // Reused an already-rendered WebView — its content is
            // already visible (no onPageCommitVisible will fire again
            // for an old, already-loaded page), so reply immediately
            // instead of waiting for a page-load event that isn't
            // coming.
            sendSurfacePackageReply(replyTo)
        }
    }

    private fun sendSurfacePackageReply(replyTo: Messenger?) {
        val host = viewHost
        if (host == null || replyTo == null) return
        val surfacePackage = host.surfacePackage
        if (surfacePackage == null) {
            replyErrorTo(replyTo, "surface_package_null")
            return
        }
        val replyData = Bundle().apply {
            putParcelable(KEY_SURFACE_PACKAGE, surfacePackage)
        }
        val reply = Message.obtain(null, MSG_ATTACHED)
        reply.setData(replyData)
        try {
            replyTo.send(reply)
        } catch (_: Exception) {
            // Host side may already be gone (e.g. Flutter view disposed
            // mid-flight) — nothing to recover here, just don't crash
            // this process over it.
        }
    }

    private fun replyErrorTo(replyTo: Messenger, code: String) {
        val replyData = Bundle().apply { putString(KEY_ERROR, code) }
        val reply = Message.obtain(null, MSG_ATTACH_FAILED)
        reply.setData(replyData)
        try {
            replyTo.send(reply)
        } catch (_: Exception) {
        }
    }

    private fun release() {
        webView?.apply {
            stopLoading()
            clearHistory()
            (parent as? android.view.ViewGroup)?.removeView(this)
            destroy()
        }
        webView = null
        viewHost?.release()
        viewHost = null
    }

    override fun onDestroy() {
        release()
        super.onDestroy()
    }

    companion object {
        const val MSG_ATTACH = 1
        const val MSG_ATTACHED = 2
        const val MSG_ATTACH_FAILED = 3
        const val MSG_RESIZE = 4
        const val MSG_RELEASE = 5

        const val KEY_HOST_TOKEN = "hostToken"
        const val KEY_DISPLAY_ID = "displayId"
        const val KEY_WIDTH = "width"
        const val KEY_HEIGHT = "height"
        const val KEY_ACCOUNT_ID = "accountId"
        const val KEY_INITIAL_URL = "initialUrl"
        const val KEY_SURFACE_PACKAGE = "surfacePackage"
        const val KEY_ERROR = "error"
    }
}

// One trivial subclass per process slot — see AndroidManifest.xml, each
// declared with its own distinct `android:process` value. Must match
// SlotAllocator.slotCount on the Dart side.
class WebViewSlotService0 : WebViewSlotService()
class WebViewSlotService1 : WebViewSlotService()
class WebViewSlotService2 : WebViewSlotService()
class WebViewSlotService3 : WebViewSlotService()
class WebViewSlotService4 : WebViewSlotService()
class WebViewSlotService5 : WebViewSlotService()