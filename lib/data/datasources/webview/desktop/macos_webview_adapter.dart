import 'dart:async';
import 'dart:io';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/repositories/webview_adapter.dart';

class MacOSWebViewAdapter implements WebViewAdapter {
  @override
  WebViewEngineKind get engineKind => WebViewEngineKind.wkWebViewMac;

  @override
  Future<IsolationProbeResult> probeIsolationSupport() async {
    final osVersionMajor = await _macOSMajorVersion();

    if (osVersionMajor == null) {
      return const IsolationProbeResult(
        isSupported: false,
        engine: WebViewEngineKind.wkWebViewMac,
        isNativeIsolation: false,
        reason: 'Could not determine macOS version.',
      );
    }

    if (osVersionMajor >= AppConstants.minMacOSMajorVersionForIsolation) {
      return const IsolationProbeResult(
        isSupported: true,
        engine: WebViewEngineKind.wkWebViewMac,
        isNativeIsolation: true,
        reason: 'macOS 14+: WKWebsiteDataStore(forIdentifier:) available.',
      );
    }

    return const IsolationProbeResult(
      isSupported: false,
      engine: WebViewEngineKind.wkWebViewMac,
      isNativeIsolation: false,
      reason:
          'macOS < 14 has no native persistent isolated WKWebView '
          'data store. Needs explicit fallback decision per PRD §24.',
    );
  }

  Future<int?> _macOSMajorVersion() async {
    try {
      final result = await Process.run('sw_vers', ['-productVersion']);
      final version = (result.stdout as String).trim();
      return int.tryParse(version.split('.').first);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<WebViewSessionHandle> createOrResumeSession({
    required String accountId,
    required String sessionPath,
  }) async {
    return _MacOSSessionHandle(accountId: accountId);
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

class _MacOSSessionHandle implements WebViewSessionHandle {
  _MacOSSessionHandle({required this.accountId});

  @override
  final String accountId;

  final _statusController =
      StreamController<AccountConnectionStatus>.broadcast();

  @override
  Stream<AccountConnectionStatus> get statusStream => _statusController.stream;

  @override
  Future<void> navigateToWhatsAppWeb() async {
    _statusController.add(AccountConnectionStatus.connecting);
  }

  @override
  Future<void> reload() async {}

  @override
  Future<void> pauseRendering() async {}

  @override
  Future<void> resumeRendering() async {}

  @override
  Future<void> unloadFromMemory() async {}

  @override
  Future<int?> approximateMemoryBytes() async => null;

  @override
  Future<void> clearSessionData() async {}

  @override
  Future<void> dispose() async {
    await _statusController.close();
  }
}
