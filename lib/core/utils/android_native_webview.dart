import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/repositories/webview_adapter.dart';

/// Android-only native WebView session, backed by
/// `nativewebview/NativeWebView.kt` (a hybrid-composition PlatformView
/// wrapping android.webkit.WebView directly — no `flutter_inappwebview`
/// dependency at all, avoiding any risk of it re-introducing a Windows
/// build conflict).
///
/// Isolation: `androidx.webkit`'s Multi-Profile API (see NativeWebView.kt
/// doc) — genuinely separate cookie/localStorage/IndexedDB per account,
/// without the "only once per process" limitation the old
/// `setDataDirectorySuffix` API (and this app's earlier WebView2
/// Windows saga) both hit.
class AndroidNativeWebViewSessionHandle implements WebViewSessionHandle {
  AndroidNativeWebViewSessionHandle({required this.accountId});

  @override
  final String accountId;

  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// Set once the platform view is created (see
  /// [AndroidNativeWebView.onPlatformViewCreated]) — everything before
  /// that point queues via [_pendingCalls] instead of throwing, since
  /// widget creation is async relative to this handle's own lifecycle.
  MethodChannel? _channel;
  final _pendingCalls = <Future<void> Function(MethodChannel)>[];

  final ValueNotifier<bool> desktopModeEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> shouldBeMounted = ValueNotifier<bool>(true);
  bool isolationSupported = false;

  final _statusController =
  StreamController<AccountConnectionStatus>.broadcast();

  @override
  Stream<AccountConnectionStatus> get statusStream => _statusController.stream;

  void bindChannel(int viewId) {
    _channel = MethodChannel('multi_whatsapp_web/native_webview_$viewId');
    // Flush anything queued before the platform view finished creating.
    for (final call in _pendingCalls) {
      unawaited(call(_channel!));
    }
    _pendingCalls.clear();
    unawaited(_refreshIsolationSupport());
  }

  Future<void> _refreshIsolationSupport() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      isolationSupported =
          await channel.invokeMethod<bool>('isIsolationSupported') ?? false;
    } catch (_) {
      isolationSupported = false;
    }
  }

  Future<void> _call(
      String method, [
        Map<String, dynamic>? args,
      ]) async {
    final channel = _channel;
    if (channel == null) {
      // Queue until the platform view is actually created.
      _pendingCalls.add((c) => c.invokeMethod(method, args));
      return;
    }
    await channel.invokeMethod(method, args);
  }

  @override
  Future<void> navigateToWhatsAppWeb() async {
    _statusController.add(AccountConnectionStatus.connecting);
    await _call('loadUrl', {'url': AppConstants.whatsappWebUrl});
    // TODO: bridge a DOM observer (QR canvas vs. chat list) via
    // evaluateJavascript + a JS-to-Dart channel for accurate
    // connecting/connected/disconnected/error status — no public
    // WhatsApp Web JS status API exists.
  }

  Future<void> setDesktopMode(bool enabled) async {
    if (desktopModeEnabled.value == enabled) return;
    desktopModeEnabled.value = enabled;
    await _call('setUserAgent', {'userAgent': enabled ? desktopUserAgent : null});
    try {
      await _call('evaluateJavascript', {
        'script': '''
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
      });
    } catch (_) {}
    await _call('loadUrl', {'url': AppConstants.whatsappWebUrl});
  }

  @override
  Future<void> reload() => _call('reload');

  @override
  Future<void> pauseRendering() => _call('pauseRendering', {'hidden': true});

  @override
  Future<void> resumeRendering() => _call('resumeRendering', {'hidden': false});

  @override
  Future<void> unloadFromMemory() async {
    // Signal the widget to unmount the AndroidView — dispose() on the
    // Kotlin side (webView.destroy()) is what actually releases native
    // memory, triggered by the platform view's own disposal when it's
    // removed from the tree.
    shouldBeMounted.value = false;
  }

  @override
  Future<int?> approximateMemoryBytes() async => null;

  @override
  Future<void> clearSessionData() async {
    await _call('clearCache');
    await _call('clearCookies');
  }

  @override
  Future<void> dispose() async {
    await unloadFromMemory();
    shouldBeMounted.dispose();
    desktopModeEnabled.dispose();
    await _statusController.close();
  }
}

/// The actual embedded native view — build this wherever the app
/// currently builds `InAppWebView`/`WebViewWidget` for mobile (see
/// `webview_container.dart`'s `_MobileEngineSurface`).
class AndroidNativeWebView extends StatelessWidget {
  const AndroidNativeWebView({super.key, required this.handle});

  final AndroidNativeWebViewSessionHandle handle;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: handle.shouldBeMounted,
      builder: (context, mounted, _) {
        if (!mounted) return const SizedBox.shrink();
        return AndroidView(
          viewType: 'multi_whatsapp_web/native_webview',
          creationParams: {
            'accountId': handle.accountId,
            'initialUrl': AppConstants.whatsappWebUrl,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: handle.bindChannel,
        );
      },
    );
  }
}