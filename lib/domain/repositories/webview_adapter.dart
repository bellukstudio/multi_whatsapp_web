import '../../core/constants/app_constants.dart';

class IsolationProbeResult {
  const IsolationProbeResult({
    required this.isSupported,
    required this.engine,
    required this.isNativeIsolation,
    this.reason,
  });

  final bool isSupported;
  final WebViewEngineKind engine;

  final bool isNativeIsolation;

  final String? reason;
}

abstract class WebViewSessionHandle {
  String get accountId;

  Stream<AccountConnectionStatus> get statusStream;

  Future<void> navigateToWhatsAppWeb();

  Future<void> reload();

  Future<void> pauseRendering();

  Future<void> resumeRendering();

  Future<void> unloadFromMemory();

  Future<int?> approximateMemoryBytes();

  Future<void> clearSessionData();

  Future<void> dispose();
}

abstract class WebViewAdapter {
  WebViewEngineKind get engineKind;

  Future<IsolationProbeResult> probeIsolationSupport();

  Future<WebViewSessionHandle> createOrResumeSession({
    required String accountId,
    required String sessionPath,
  });

  Future<WebViewSessionHandle> reloadFromPersistedStorage({
    required String accountId,
    required String sessionPath,
  });
}
