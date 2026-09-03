import '../../../../domain/repositories/webview_adapter.dart';
import 'slot_embed_webview_session_handle.dart';
import '../../../../core/constants/app_constants.dart';
class AndroidWebViewAdapter implements WebViewAdapter {
  @override
  WebViewEngineKind get engineKind => WebViewEngineKind.inAppWebViewAndroid;

  @override
  Future<IsolationProbeResult> probeIsolationSupport() async {
    return const IsolationProbeResult(
      isSupported: true,
      engine: WebViewEngineKind.inAppWebViewAndroid,
      isNativeIsolation: true,
      reason: 'Each account runs its native WebView in its own dedicated '
          'OS process (android:process), projected into the Flutter UI '
          'via SurfaceControlViewHost — genuine per-account cookie/'
          'localStorage/IndexedDB isolation, embedded in place rather '
          'than a separate screen. Requires Android 11+ (API 30+); '
          'limited to ${SlotAllocator.slotCount} concurrently-open '
          'accounts per app run.',
    );
  }

  @override
  Future<WebViewSessionHandle> createOrResumeSession({
    required String accountId,
    required String sessionPath,
    String? accountName,
  }) async {
    return SlotEmbedWebViewSessionHandle(
      accountId: accountId,
      accountName: accountName ?? accountId,
    );
  }

  @override
  Future<WebViewSessionHandle> reloadFromPersistedStorage({
    required String accountId,
    required String sessionPath,
    String? accountName,
  }) {
    return createOrResumeSession(
      accountId: accountId,
      sessionPath: sessionPath,
      accountName: accountName,
    );
  }
}