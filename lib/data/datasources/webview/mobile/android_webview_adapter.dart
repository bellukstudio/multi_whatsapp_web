import 'package:multi_whatsapp_web/core/constants/app_constants.dart';

import '../../../../domain/repositories/webview_adapter.dart';
import 'mobile_webview_session_handle.dart';

/// PRD §24 row 4 — Android, now via `webview_flutter` instead of
/// `flutter_inappwebview` (see `mobile_webview_session_handle.dart` for
/// why this switch happened).
///
/// used `dataDirectorySuffix` (Android 10+ / API 29+) as its per-account
/// isolation primitive, and this probe reported `isSupported: true` only
/// above that SDK level. `webview_flutter_android`'s public API has no
/// equivalent — there is currently NO native per-account data-directory
/// isolation in this adapter. `probeIsolationSupport()` below reports
/// this honestly (`isSupported: false`) rather than silently claiming a
/// guarantee that no longer holds. See
/// `mobile_webview_session_handle.dart`'s class doc for the two
/// realistic ways to restore real isolation if/when needed.
class AndroidWebViewAdapter implements WebViewAdapter {
  @override
  WebViewEngineKind get engineKind => WebViewEngineKind.inAppWebViewAndroid;

  @override
  Future<IsolationProbeResult> probeIsolationSupport() async {
    return const IsolationProbeResult(
      isSupported: false,
      engine: WebViewEngineKind.inAppWebViewAndroid,
      isNativeIsolation: false,
      reason: 'webview_flutter (the package now used on Android, after '
          'moving off flutter_inappwebview to resolve a Windows-only '
          'DispatcherQueueController conflict) has no public API for a '
          'per-instance data-directory suffix. Accounts currently share '
          'one cookie/localStorage store on Android. See '
          'mobile_webview_session_handle.dart doc comment for how to '
          'restore genuine isolation if this is required before shipping.',
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
    // PRD §11: mobile OS may fully kill the WebView process while
    // backgrounded. Creating fresh picks back up whatever the shared
    // cookie jar currently holds — see the TODO ISOLATION note above for
    // the caveat this now carries around multi-account correctness.
    return createOrResumeSession(accountId: accountId, sessionPath: sessionPath);
  }
}