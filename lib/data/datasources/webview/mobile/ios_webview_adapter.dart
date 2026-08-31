import 'package:multi_whatsapp_web/core/constants/app_constants.dart';

import '../../../../domain/repositories/webview_adapter.dart';
import 'mobile_webview_session_handle.dart';

/// PRD §24 row 5 — iOS, now via `webview_flutter` (WKWebView under the
/// hood) instead of `flutter_inappwebview` (see
/// `mobile_webview_session_handle.dart` for why this switch happened).
///
/// used a `WKWebsiteDataStore(forIdentifier:)` (iOS 17+) as its
/// per-account isolation primitive, gated behind an iOS-version probe.
/// `webview_flutter_wkwebview`'s public API has no equivalent exposed —
/// there is currently NO native per-account data-store isolation in this
/// adapter, on any iOS version. `probeIsolationSupport()` below reports
/// this honestly rather than silently claiming a guarantee that no
/// longer holds. See `mobile_webview_session_handle.dart`'s class doc
/// for the two realistic ways to restore real isolation if/when needed.
class IOSWebViewAdapter implements WebViewAdapter {
  @override
  WebViewEngineKind get engineKind => WebViewEngineKind.inAppWebViewIOS;

  @override
  Future<IsolationProbeResult> probeIsolationSupport() async {
    return const IsolationProbeResult(
      isSupported: false,
      engine: WebViewEngineKind.inAppWebViewIOS,
      isNativeIsolation: false,
      reason: 'webview_flutter_wkwebview (the package now used on iOS, '
          'after moving off flutter_inappwebview to resolve a '
          'Windows-only DispatcherQueueController conflict) has no '
          'public API for a per-instance WKWebsiteDataStore identifier. '
          'Accounts currently share one cookie/localStorage store on '
          'iOS. See mobile_webview_session_handle.dart doc comment for '
          'how to restore genuine isolation if this is required before '
          'shipping.',
    );
  }

  @override
  Future<WebViewSessionHandle> createOrResumeSession({
    required String accountId,
    required String sessionPath,
  }) async {
    return MobileWebViewSessionHandle(accountId: accountId);
  }

  @override
  Future<WebViewSessionHandle> reloadFromPersistedStorage({
    required String accountId,
    required String sessionPath,
  }) {
    return createOrResumeSession(accountId: accountId, sessionPath: sessionPath);
  }
}