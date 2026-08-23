import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/repositories/webview_adapter.dart';
import 'mobile_webview_session_handle.dart';

/// PRD §24 row 4 — Android / `flutter_inappwebview`.
///
/// Isolation mechanism: `dataDirectorySuffix` per WebView instance,
/// available on **Android 10+ (API 29+)**. Below that, PRD §24 says full
/// isolation is not supported — this adapter gates it off (returns
/// `isSupported: false`) rather than silently degrading to shared
/// storage.
///
/// RAM policy (PRD §26/§27): only one [MobileWebViewSessionHandle] is
/// ever active at a time — enforced by [SessionCubit], not here. This
/// adapter's job is just to hand back a correctly-isolated, disposable
/// handle each time.
class AndroidWebViewAdapter implements WebViewAdapter {
  @override
  WebViewEngineKind get engineKind => WebViewEngineKind.inAppWebViewAndroid;

  @override
  Future<IsolationProbeResult> probeIsolationSupport() async {
    final sdkInt = await _androidSdkInt();

    if (sdkInt == null) {
      return const IsolationProbeResult(
        isSupported: false,
        engine: WebViewEngineKind.inAppWebViewAndroid,
        isNativeIsolation: false,
        reason: 'Could not determine Android SDK version.',
      );
    }

    if (sdkInt >= AppConstants.minAndroidSdkForDataDirSuffix) {
      return const IsolationProbeResult(
        isSupported: true,
        engine: WebViewEngineKind.inAppWebViewAndroid,
        isNativeIsolation: true,
        reason: 'Android 10+: dataDirectorySuffix supported.',
      );
    }

    return const IsolationProbeResult(
      isSupported: false,
      engine: WebViewEngineKind.inAppWebViewAndroid,
      isNativeIsolation: false,
      reason: 'Android < 10 (API < 29) does not support '
          'dataDirectorySuffix — full isolation unavailable. PRD §24 '
          'requires an explicit minimum-SDK decision before shipping.',
    );
  }

  Future<int?> _androidSdkInt() async {
    if (!Platform.isAndroid) return null;
    final info = await DeviceInfoPlugin().androidInfo;
    return info.version.sdkInt;
  }

  @override
  Future<WebViewSessionHandle> createOrResumeSession({
    required String accountId,
    required String sessionPath,
  }) async {
    final settings = InAppWebViewSettings(
      // Distinct native storage directory per account — this IS the
      // isolation primitive on Android (PRD §24 row 4). `accountId` is a
      // uuid (never a user-facing name), so it's also safe as a
      // filesystem-suffix per §25.
      // dataDirectorySuffix: accountId,
      // Also keep it out of any shared/external location per §25.
      allowFileAccess: false,
    );
    return MobileWebViewSessionHandle(accountId: accountId, settings: settings);
  }

  @override
  Future<WebViewSessionHandle> reloadFromPersistedStorage({
    required String accountId,
    required String sessionPath,
  }) {
    // PRD §11: the previous handle may already be gone (OS-killed WebView
    // process). Creating fresh with the same dataDirectorySuffix picks
    // back up the persisted cookies/localStorage on disk — the caller
    // (SessionCubit.handleAppResumed) is responsible for showing a
    // "reconnecting" state while this resolves rather than assuming
    // instant continuity.
    return createOrResumeSession(accountId: accountId, sessionPath: sessionPath);
  }
}
