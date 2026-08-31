import 'package:multi_whatsapp_web/core/constants/app_constants.dart';
import 'package:multi_whatsapp_web/core/utils/android_native_webview.dart';

import '../../../../domain/repositories/webview_adapter.dart';

/// PRD §24 row 4 — Android, now on a fully native
/// `AndroidView`/`android.webkit.WebView` platform view (see
/// `android_native_webview_session_handle.dart` +
/// `android/.../nativewebview/NativeWebView.kt`) instead of
/// `flutter_inappwebview`, per explicit decision to avoid that
/// dependency's Windows-build risk entirely (even though the
/// `flutter_inappwebview_windows` no-op stub built earlier would have
/// handled it — this removes the dependency altogether instead).
///
/// Isolation via `androidx.webkit`'s Multi-Profile API (ProfileStore) —
/// see NativeWebView.kt's class doc for exact mechanism + the ⚠️ VERIFY
/// note on the one part of that wiring worth double-checking against
/// your resolved androidx.webkit version.
class AndroidWebViewAdapter implements WebViewAdapter {
  @override
  WebViewEngineKind get engineKind => WebViewEngineKind.inAppWebViewAndroid;

  @override
  Future<IsolationProbeResult> probeIsolationSupport() async {
    // The real answer only becomes known once the native platform view
    // has been created and reports back via `isIsolationSupported` (see
    // AndroidNativeWebViewSessionHandle) — this probe can only report
    // the *mechanism*, not a live yes/no, ahead of that.
    return const IsolationProbeResult(
      isSupported: true,
      engine: WebViewEngineKind.inAppWebViewAndroid,
      isNativeIsolation: true,
      reason: 'Native android.webkit.WebView via androidx.webkit '
          'Multi-Profile API (ProfileStore) — separate cookie/'
          'localStorage/IndexedDB profile per account, on WebView '
          'runtimes that support it (WebView 108+). Falls back to one '
          'shared profile on older WebView runtimes; check '
          'AndroidNativeWebViewSessionHandle.isolationSupported after '
          'the session is created for the live, per-device answer.',
    );
  }

  @override
  Future<WebViewSessionHandle> createOrResumeSession({
    required String accountId,
    required String sessionPath,
  }) async {
    return AndroidNativeWebViewSessionHandle(accountId: accountId);
  }

  @override
  Future<WebViewSessionHandle> reloadFromPersistedStorage({
    required String accountId,
    required String sessionPath,
  }) {
    return createOrResumeSession(accountId: accountId, sessionPath: sessionPath);
  }
}