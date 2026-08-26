// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/repositories/webview_adapter.dart';

/// Shared engine for Android + iOS (both ride on `flutter_inappwebview`,
/// PRD §40) — only the isolation *settings* differ per platform (see
/// [AndroidWebViewAdapter] / [IOSWebViewAdapter]), not the lifecycle
/// mechanics here.
///
/// RAM-critical detail (PRD §26/§27): `InAppWebViewController` is bound
/// to a live native Android/iOS View owned by the widget tree — calling
/// `controller.dispose()` alone is not enough to release native memory
/// while the `InAppWebView` widget is still mounted. This handle exposes
/// [shouldBeMounted] (a [ValueListenable]) so [WebViewContainer] can
/// actually unmount the widget on [unloadFromMemory], which is what lets
/// the native View + its underlying Chromium/WKWebView instance be
/// garbage-collected — hiding it with `Offstage`/`Visibility` would NOT
/// free the memory.
class MobileWebViewSessionHandle implements WebViewSessionHandle {
  MobileWebViewSessionHandle({
    required this.accountId,
    required this.settings,
    bool desktopModeEnabled = false,
  }) : desktopModeEnabled = ValueNotifier<bool>(desktopModeEnabled);

  @override
  final String accountId;

  /// Platform-specific isolation settings, e.g.
  /// `InAppWebViewSettings(dataDirectorySuffix: accountId)` on Android or
  /// the iOS 17+ `websiteDataStore` identifier equivalent — filled in by
  /// the per-platform adapter (PRD §24 row 4/5).
  ///
  /// This is the settings object passed to the *initial* `InAppWebView`
  /// build. It intentionally does NOT bake in desktop-mode fields —
  /// those are layered on top at runtime via [_applyDesktopModeIfNeeded]
  /// once the controller exists, so isolation settings (data directory /
  /// data store identity) stay owned entirely by the adapter that built
  /// this handle.
  final InAppWebViewSettings settings;

  /// UA string WhatsApp Web is checked against to decide whether to serve
  /// its desktop (multi-device) layout instead of redirecting mobile
  /// clients to the app-store / "use WhatsApp on your phone" screen.
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// Android Chromium WebViews still report Client Hints
  /// (`navigator.userAgentData`) reflecting the REAL device, independent
  /// of whatever `userAgent` string is set. Sites that check
  /// `userAgentData.mobile` first (before falling back to the legacy UA
  /// string) will still detect "mobile" unless this is overridden too —
  /// this is what Chrome's own "Request Desktop Site" does under the
  /// hood beyond just swapping the UA string.
  static const String _desktopUAOverrideScript = '''
(function() {
  try {
    Object.defineProperty(navigator, 'userAgentData', {
      get: function() {
        return {
          brands: [
            {brand: 'Not.A.Brand', version: '8'},
            {brand: 'Chromium', version: '124'},
            {brand: 'Google Chrome', version: '124'}
          ],
          mobile: false,
          platform: 'Windows'
        };
      },
      configurable: true
    });
  } catch (e) {}
})();
''';

  InAppWebViewController? _controller;
  bool _pendingNavigate = false;

  /// Whether desktop mode is on for THIS account's session. A
  /// [ValueNotifier] (not plain state routed through SessionCubit) so UI
  /// listening to it — e.g. a Settings switch — updates reliably even
  /// though this handle is a long-lived mutable object rather than an
  /// Equatable value compared by SessionCubit's Bloc state.
  final ValueNotifier<bool> desktopModeEnabled;

  final _statusController =
      StreamController<AccountConnectionStatus>.broadcast();

  /// Widget-tree contract: [WebViewContainer] must only build an
  /// `InAppWebView` for this handle while this is `true`. Flipping it to
  /// `false` and letting the widget rebuild (removing the InAppWebView
  /// element) is what actually releases native memory — see class doc.
  final ValueNotifier<bool> shouldBeMounted = ValueNotifier<bool>(true);

  @override
  Stream<AccountConnectionStatus> get statusStream => _statusController.stream;

  /// Called by [WebViewContainer]'s `onWebViewCreated` once the native
  /// view exists. Anything requested before this (e.g.
  /// [navigateToWhatsAppWeb] called immediately after
  /// `createOrResumeSession`) is replayed here.
  void bindController(InAppWebViewController controller) {
    _controller = controller;
    // Desktop mode has to be (re)applied every time a *new* native
    // controller is bound — e.g. after this handle survives an account
    // switch/remount — since it lives on the controller/native view, not
    // on this Dart object.
    unawaited(_applyDesktopModeIfNeeded());
    if (_pendingNavigate) {
      _pendingNavigate = false;
      unawaited(_load());
    }
  }

  /// Turns desktop mode on/off for THIS account only. Applies the UA
  /// string, `preferredContentMode` (iOS only), and the Client Hints
  /// override script (Android), then reloads so WhatsApp Web re-serves
  /// the layout matching the new identity. Changing settings alone does
  /// not retroactively re-render an already-loaded page, and WhatsApp
  /// Web is a PWA with a service worker that can re-serve a cached
  /// mobile bundle unless the cache is cleared first.
  Future<void> setDesktopMode(bool enabled) async {
    if (desktopModeEnabled.value == enabled) return;
    desktopModeEnabled.value = enabled;
    await _applyDesktopModeIfNeeded();
    await _purgeServiceWorkerAndCaches();
    // Fresh navigation instead of reload() — reload() can still be
    // intercepted by whatever the (now-unregistering) service worker's
    // fetch handler does mid-transition. A clean loadUrl after the purge
    // above is more reliable than reload() for forcing a true fresh load.
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(AppConstants.whatsappWebUrl)),
    );
  }

  /// WhatsApp Web is a PWA: its service worker intercepts navigation and
  /// can re-serve an already-cached mobile-layout bundle from the Cache
  /// Storage API regardless of `userAgent`/Client Hints changes, and
  /// regardless of `controller.clearCache()` (which only clears the plain
  /// HTTP cache, not Cache Storage). This must be purged explicitly or
  /// toggling desktop mode has no visible effect.
  Future<void> _purgeServiceWorkerAndCaches() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(
        source: '''
      (async function() {
        try {
          const regs = await navigator.serviceWorker.getRegistrations();
          for (const r of regs) { await r.unregister(); }
        } catch (e) {}
        try {
          const keys = await caches.keys();
          for (const k of keys) { await caches.delete(k); }
        } catch (e) {}
      })();
    ''',
      );
    } catch (_) {
      // Best-effort — if the page hasn't finished loading yet or JS
      // execution fails for any reason, still proceed to loadUrl below
      // rather than blocking the toggle.
    }
    // Also clear the native-level WebView storage (separate from the
    // above JS-level purge) so nothing at the platform layer is holding
    // onto old cached responses either.
    try {
      await InAppWebViewController.clearAllCache();
    } catch (_) {}
  }

  Future<void> _applyDesktopModeIfNeeded() async {
    final controller = _controller;
    if (controller == null) return;

    await controller.setSettings(
      settings: InAppWebViewSettings(
        userAgent: desktopModeEnabled.value ? desktopUserAgent : '',
        preferredContentMode: desktopModeEnabled.value
            ? UserPreferredContentMode.DESKTOP
            : UserPreferredContentMode.RECOMMENDED,
      ),
    );

    // Re-inject (or remove) the Client Hints override script each time
    // this is called, rather than only once — removeAllUserScripts()
    // clears whatever was there before so toggling off doesn't leave a
    // stale override behind.
    await controller.removeAllUserScripts();
    if (desktopModeEnabled.value) {
      await controller.addUserScript(
        userScript: UserScript(
          source: _desktopUAOverrideScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      );
    }
  }

  @override
  Future<void> navigateToWhatsAppWeb() async {
    _statusController.add(AccountConnectionStatus.connecting);
    if (_controller == null) {
      // Widget not mounted/created yet (e.g. right after
      // createOrResumeSession()) — defer until bindController fires.
      _pendingNavigate = true;
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    await _controller!.loadUrl(
      urlRequest: URLRequest(url: WebUri(AppConstants.whatsappWebUrl)),
    );
    // canvas vs. chat list presence) to emit accurate
    // connecting/connected/disconnected/error on statusStream — there is
    // no public WhatsApp Web JS status API.
  }

  @override
  Future<void> reload() async {
    await _controller?.reload();
  }

  @override
  Future<void> pauseRendering() async {
    // Not used on mobile in the current policy (single active session,
    // §27) — inactive accounts go straight to unloadFromMemory. Kept
    // implemented for interface completeness / future desktop-like pool
    // experiments on tablets.
    await _controller?.evaluateJavascript(
      source: _visibilityScript(hidden: true),
    );
  }

  @override
  Future<void> resumeRendering() async {
    await _controller?.evaluateJavascript(
      source: _visibilityScript(hidden: false),
    );
  }

  String _visibilityScript({required bool hidden}) =>
      '''
    Object.defineProperty(document, 'hidden', {value: $hidden, configurable: true});
    document.dispatchEvent(new Event('visibilitychange'));
  ''';

  @override
  Future<void> unloadFromMemory() async {
    // Step 1: signal WebViewContainer to unmount the InAppWebView widget.
    // Step 2 (below): dispose the controller once it's safely detached.
    shouldBeMounted.value = false;
    // whether InAppWebViewController exposes a public dispose() for
    // widget-bound (non-headless) controllers — some versions rely on
    // the widget's own dispose lifecycle instead. If no public method
    // exists, unmounting via [shouldBeMounted] above is the primary
    // release mechanism and this call should be removed.
    try {
      _controller?.dispose();
    } catch (_) {
      // Swallow: dispose() may not be supported on all versions/platforms
      // for a widget-bound controller — unmounting is still effective.
    }
    _controller = null;
  }

  @override
  Future<int?> approximateMemoryBytes() async {
    // flutter_inappwebview doesn't expose a per-instance memory API on
    // either platform; callers fall back to whole-process RSS via
    // MemoryProfiler instead.
    return null;
  }

  @override
  Future<void> clearSessionData() async {
    await CookieManager.instance().deleteAllCookies();
    await _controller?.clearCache();
    // NOTE (verify during PoC #2/#5, PRD §24): clearCache()/cookie
    // deletion granularity depends on whether the platform actually
    // isolates storage per dataDirectorySuffix/websiteDataStore
    // identifier at the native layer, vs. sharing a single WebView
    // storage backend. If isolation is confirmed working (per
    // probeIsolationSupport), this only affects THIS account; if not,
    // treat probeIsolationSupport's false result as blocking, per §24.
  }

  @override
  Future<void> dispose() async {
    await unloadFromMemory();
    shouldBeMounted.dispose();
    desktopModeEnabled.dispose();
    await _statusController.close();
  }
}
