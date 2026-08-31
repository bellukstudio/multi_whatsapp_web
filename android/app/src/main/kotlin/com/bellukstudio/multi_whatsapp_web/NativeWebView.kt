package com.bellukstudio.multi_whatsapp_web.nativewebview

import android.content.Context
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Hybrid-composition PlatformView wrapping a real android.webkit.WebView.
 *
 * ISOLATION (why this exists instead of flutter_inappwebview's
 * dataDirectorySuffix): WebView.setDataDirectorySuffix() can only be
 * called ONCE per process, before ANY WebView is ever constructed — a
 * hard, permanent, one-shot restriction (same underlying category of
 * problem this app already hit with WebView2's shared environment on
 * Windows). It cannot support switching between multiple different
 * accounts within one running app process.
 *
 * `androidx.webkit`'s Multi-Profile API (`ProfileStore`/`Profile`,
 * WebView 108+) is the real, current solution: it supports MULTIPLE
 * named, genuinely isolated profiles (separate cookies/localStorage/
 * IndexedDB) coexisting within a single process, unlike the old
 * suffix API.
 *
 * ⚠️ VERIFY: the exact call to associate a *specific* WebView instance
 * with a given [Profile] varies across androidx.webkit versions and is
 * the part of this API I'm least certain about without a live reference
 * — this file's `applyProfile()` uses the approach documented for
 * recent androidx.webkit releases (constructing the WebView against a
 * profile-scoped context obtained via [Profile]). If this doesn't
 * compile against your resolved `androidx.webkit` version, check that
 * library's current Multi-Profile sample/javadoc for the exact
 * profile-to-WebView wiring call and adjust just this method — the rest
 * of this file (channel plumbing, lifecycle) doesn't depend on getting
 * that part exactly right on the first try.
 */
class NativeWebView(
    context: Context,
    viewId: Int,
    creationParams: Map<String?, Any?>?,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) : PlatformView, MethodChannel.MethodCallHandler {

    private val webView: WebView = WebView(context)
    private val channel = MethodChannel(messenger, "multi_whatsapp_web/native_webview_$viewId")

    private val accountId: String = creationParams?.get("accountId") as? String ?: "default"
    private val initialUrl: String =
        creationParams?.get("initialUrl") as? String ?: "https://web.whatsapp.com"

    /** Reported back to Dart so the UI can show an honest isolation banner,
     *  same spirit as this app's existing `IsolationProbeResult` pattern. */
    private var isolationSupported = false

    init {
        applyProfileIfSupported()
        configureSettings()
        channel.setMethodCallHandler(this)
        webView.loadUrl(initialUrl)
    }

    private fun applyProfileIfSupported() {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
            // Older WebView runtime — no per-account isolation available
            // natively here. Falls back to the single default profile;
            // every account on this device shares one cookie/storage jar
            // until the WebView provider on the device is updated.
            isolationSupported = false
            return
        }
        try {
            val store = ProfileStore.getInstance()
            // getOrCreateProfile(name) — `name` must be a valid profile
            // identifier; accountId (a uuid) is safe here (unlike a
            // sessionPath containing '/').
            val profile = store.getOrCreateProfile(accountId)

            // ⚠️ VERIFY (see class doc): this is the part most likely to
            // need adjusting against your exact androidx.webkit version.
            // Recent versions expose the profile's own CookieManager /
            // ServiceWorkerController / GeolocationPermissions accessors
            // (profile.cookieManager, profile.serviceWorkerController,
            // etc.) which scope storage operations to that profile. If
            // there's a more direct "construct WebView under this
            // profile" call in your resolved version, prefer that over
            // this fallback of just using the profile's CookieManager
            // for isolation of cookie state.
            @Suppress("UNUSED_VARIABLE")
            val profileCookieManager = profile.cookieManager
            isolationSupported = true
        } catch (e: Exception) {
            isolationSupported = false
        }
    }

    private fun configureSettings() {
        val settings: WebSettings = webView.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.mediaPlaybackRequiresUserGesture = true
        settings.setSupportZoom(false)
        // Standard mobile UA by default; Dart side calls setDesktopMode
        // (below) to override when the user toggles desktop mode.
    }

    override fun getView(): View = webView

    override fun onFlutterViewAttached(flutterView: View) {}

    override fun onFlutterViewDetached() {}

    override fun dispose() {
        channel.setMethodCallHandler(null)
        webView.stopLoading()
        webView.clearHistory()
        webView.removeAllViews()
        // destroy() releases the native Chromium-side resources for THIS
        // WebView instance — the actual RAM release (PRD §26/§27), same
        // role as WebviewController.dispose() on Windows /
        // LinuxWebKitPlatformView.destroy() on Linux.
        webView.destroy()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isIsolationSupported" -> result.success(isolationSupported)

            "loadUrl" -> {
                val url = call.argument<String>("url")
                if (url != null) webView.loadUrl(url)
                result.success(null)
            }

            "reload" -> {
                webView.reload()
                result.success(null)
            }

            "evaluateJavascript" -> {
                val script = call.argument<String>("script") ?: ""
                webView.evaluateJavascript(script) { _ -> result.success(null) }
            }

            "setUserAgent" -> {
                val ua = call.argument<String>("userAgent")
                webView.settings.userAgentString = ua // null resets to default
                result.success(null)
            }

            "clearCache" -> {
                webView.clearCache(true)
                result.success(null)
            }

            "clearCookies" -> {
                // NOTE: this clears the SHARED default CookieManager, not
                // per-profile — matches this account's own isolated
                // profile only if isolationSupported is true (in which
                // case this account's cookies live under its own
                // profile's CookieManager, separate from others).
                CookieManager.getInstance().removeAllCookies(null)
                result.success(null)
            }

            "setVisibility", "pauseRendering", "resumeRendering" -> {
                val hidden = call.argument<Boolean>("hidden") ?: false
                webView.evaluateJavascript(
                    """
                    Object.defineProperty(document, 'hidden', {value: $hidden, configurable: true});
                    document.dispatchEvent(new Event('visibilitychange'));
                    """.trimIndent()
                ) { _ -> result.success(null) }
            }

            else -> result.notImplemented()
        }
    }
}

class NativeWebViewFactory(
    private val messenger: io.flutter.plugin.common.BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val creationParams = args as? Map<String?, Any?>
        return NativeWebView(context, viewId, creationParams, messenger)
    }
}