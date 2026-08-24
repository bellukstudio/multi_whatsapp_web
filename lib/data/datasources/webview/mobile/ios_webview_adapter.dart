import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/repositories/webview_adapter.dart';
import 'mobile_webview_session_handle.dart';

/// PRD §24 row 5 — iOS / WKWebView (via `flutter_inappwebview`).
///
/// Isolation mechanism: a `WKWebsiteDataStore` keyed by an identifier —
/// available on **iOS 17+**. PRD flags iOS as "paling ketat" of all 5
/// platforms (App Store review risk §37 + sandboxing + this version
/// gate), and places it last in the PoC order (§3).
class IOSWebViewAdapter implements WebViewAdapter {
  @override
  WebViewEngineKind get engineKind => WebViewEngineKind.inAppWebViewIOS;

  @override
  Future<IsolationProbeResult> probeIsolationSupport() async {
    final majorVersion = await _iosMajorVersion();

    if (majorVersion == null) {
      return const IsolationProbeResult(
        isSupported: false,
        engine: WebViewEngineKind.inAppWebViewIOS,
        isNativeIsolation: false,
        reason: 'Could not determine iOS version.',
      );
    }

    if (majorVersion >= AppConstants.minIOSMajorVersionForIsolation) {
      return const IsolationProbeResult(
        isSupported: true,
        engine: WebViewEngineKind.inAppWebViewIOS,
        isNativeIsolation: true,
        reason: 'iOS 17+: WKWebsiteDataStore(forIdentifier:) available '
            'via flutter_inappwebview websiteDataStore settings.',
      );
    }

    return const IsolationProbeResult(
      isSupported: false,
      engine: WebViewEngineKind.inAppWebViewIOS,
      isNativeIsolation: false,
      reason: 'iOS < 17 has no native persistent isolated WKWebView data '
          'store. PRD §24 requires an explicit decision: raise minimum '
          'OS to 17, or evaluate non-persistent store + manual cookie '
          're-injection (higher complexity/bug risk).',
    );
  }

  Future<int?> _iosMajorVersion() async {
    if (!Platform.isIOS) return null;
    final info = await DeviceInfoPlugin().iosInfo;
    final systemVersion = info.systemVersion; // e.g. "17.4.1"
    return int.tryParse(systemVersion.split('.').first);
  }

  @override
  Future<WebViewSessionHandle> createOrResumeSession({
    required String accountId,
    required String sessionPath,
  }) async {
    final probe = await probeIsolationSupport();
    if (!probe.isSupported) {
      // Deliberately fail loud rather than silently share a WKWebView
      // data store across accounts (§24 point 3: platform not PoC'd ->
      // don't proceed to full behavior).
      throw StateError(
        'iOS isolation unavailable on this OS version: ${probe.reason}',
      );
    }

    final settings = InAppWebViewSettings(
      // TODO: confirm exact flutter_inappwebview 6.x property name for
      // binding a WKWebsiteDataStore(forIdentifier:) — at time of
      // writing this is exposed as a `websiteDataStore`/
      // `dataStore`-style iOS-only setting; verify against the installed
      // package version during PoC #5 (§3) and wire the accountId-derived
      // identifier here.
      allowFileAccess: false,
      // Perf/lightweight tuning, same rationale as AndroidWebViewAdapter.
      cacheEnabled: true,
      disableDefaultErrorPage: true,
      mediaPlaybackRequiresUserGesture: true,
    );
    return MobileWebViewSessionHandle(accountId: accountId, settings: settings);
  }

  @override
  Future<WebViewSessionHandle> reloadFromPersistedStorage({
    required String accountId,
    required String sessionPath,
  }) {
    return createOrResumeSession(accountId: accountId, sessionPath: sessionPath);
  }
}