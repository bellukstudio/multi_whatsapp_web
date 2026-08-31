import 'package:multi_whatsapp_web/core/constants/app_constants.dart';

import '../../../../domain/repositories/webview_adapter.dart';
import 'mobile_webview_session_handle.dart';

class AndroidWebViewAdapter implements WebViewAdapter {
  @override
  WebViewEngineKind get engineKind => WebViewEngineKind.inAppWebViewAndroid;

  @override
  Future<IsolationProbeResult> probeIsolationSupport() async {
    return const IsolationProbeResult(
      isSupported: false,
      engine: WebViewEngineKind.inAppWebViewAndroid,
      isNativeIsolation: false,
      reason:
          'webview_flutter (the package now used on Android, after '
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
    return createOrResumeSession(
      accountId: accountId,
      sessionPath: sessionPath,
    );
  }
}
