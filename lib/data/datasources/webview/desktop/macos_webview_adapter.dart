import 'dart:async';
import 'dart:io';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/repositories/webview_adapter.dart';

/// PRD §24 row 2 — macOS / WKWebView.
///
/// Isolation mechanism: `WKWebsiteDataStore(forIdentifier:)` gives a
/// persistent, isolated data store keyed by a UUID — **but only on
/// macOS 14+**. Below that, there is no native persistent isolated
/// store, and PRD §24 requires an explicit decision (fallback manual
/// cookie management vs. refusing to run) BEFORE Phase 1 PoC.
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

    // PRD §24 decision point #2: app currently reports "not supported"
    // rather than silently mixing sessions. Flip this only after an
    // explicit product decision to build + audit a manual cookie-jar
    // fallback (§24 warns this is "lebih rawan bug cookie-bleeding").
    return const IsolationProbeResult(
      isSupported: false,
      engine: WebViewEngineKind.wkWebViewMac,
      isNativeIsolation: false,
      reason: 'macOS < 14 has no native persistent isolated WKWebView '
          'data store. Needs explicit fallback decision per PRD §24.',
    );
  }

  Future<int?> _macOSMajorVersion() async {
    // TODO: replace with package:device_info_plus MacOsDeviceInfo
    // (osRelease) for a real, tested version read.
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
    // TODO: bridge to native Swift/ObjC via a platform channel that
    // creates a WKWebView with
    // WKWebsiteDataStore(forIdentifier: UUID(uuidString: accountId)!).
    // `flutter_inappwebview`'s InAppWebView also exposes a
    // `websiteDataStore` on recent versions — evaluate reuse vs. a
    // dedicated native bridge during PoC #4 (§3).
    return _MacOSSessionHandle(accountId: accountId);
  }

  @override
  Future<WebViewSessionHandle> reloadFromPersistedStorage({
    required String accountId,
    required String sessionPath,
  }) {
    return createOrResumeSession(accountId: accountId, sessionPath: sessionPath);
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
  Future<void> pauseRendering() async {
    // TODO: same JS visibility-change trick as Windows once the native
    // bridge exists; low priority until macOS clears its own §24 PoC
    // gate above.
  }

  @override
  Future<void> resumeRendering() async {}

  @override
  Future<void> unloadFromMemory() async {
    // TODO: dispose the native WKWebView bridge once wired (PoC #4).
    // Until then this is a placeholder — macOS is not yet PoC-passed per
    // probeIsolationSupport() above, so no real session should reach
    // this handle in production.
  }

  @override
  Future<int?> approximateMemoryBytes() async => null;

  @override
  Future<void> clearSessionData() async {
    // TODO: WKWebsiteDataStore.removeData(ofTypes:modifiedSince:) for
    // this identifier's store.
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
  }
}
