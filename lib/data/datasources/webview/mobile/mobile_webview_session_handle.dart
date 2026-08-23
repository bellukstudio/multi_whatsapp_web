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
  });

  @override
  final String accountId;

  /// Platform-specific isolation settings, e.g.
  /// `InAppWebViewSettings(dataDirectorySuffix: accountId)` on Android or
  /// the iOS 17+ `websiteDataStore` identifier equivalent — filled in by
  /// the per-platform adapter (PRD §24 row 4/5).
  final InAppWebViewSettings settings;

  InAppWebViewController? _controller;
  bool _pendingNavigate = false;

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
    if (_pendingNavigate) {
      _pendingNavigate = false;
      unawaited(_load());
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
    await _controller?.evaluateJavascript(source: _visibilityScript(hidden: true));
  }

  @override
  Future<void> resumeRendering() async {
    await _controller?.evaluateJavascript(source: _visibilityScript(hidden: false));
  }

  String _visibilityScript({required bool hidden}) => '''
    Object.defineProperty(document, 'hidden', {value: $hidden, configurable: true});
    document.dispatchEvent(new Event('visibilitychange'));
  ''';

  @override
  Future<void> unloadFromMemory() async {
    // Step 1: signal WebViewContainer to unmount the InAppWebView widget.
    // Step 2 (below): dispose the controller once it's safely detached.
    shouldBeMounted.value = false;
    // TODO: verify against the installed flutter_inappwebview version
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
    await _statusController.close();
  }
}
