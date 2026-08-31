import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/repositories/webview_adapter.dart';
import 'linux_webkit_platform_view.dart';

class LinuxWebViewAdapter implements WebViewAdapter {
  @override
  WebViewEngineKind get engineKind => WebViewEngineKind.webKitGtk;

  @override
  Future<IsolationProbeResult> probeIsolationSupport() async {
    return const IsolationProbeResult(
      isSupported: false,
      engine: WebViewEngineKind.webKitGtk,
      isNativeIsolation: true,
      reason:
          'Each account gets its own WebKitWebView backed by a '
          'distinct WebKitWebsiteDataManager directory (native GTK, '
          'linux/webkit_multi_view_plugin.cc) — genuine per-account '
          'cookie/localStorage/IndexedDB isolation, embedded directly in '
          'the app window rather than a separate OS window. NOT yet '
          'verified against the §24 two-account cookie-bleed test in a '
          'real build — confirm that before treating this as passed.',
    );
  }

  Future<String> _resolveDataDir(String sessionPath) async {
    final supportDir = await getApplicationSupportDirectory();
    final absolute = p.join(supportDir.path, sessionPath);
    await Directory(absolute).create(recursive: true);
    return absolute;
  }

  @override
  Future<WebViewSessionHandle> createOrResumeSession({
    required String accountId,
    required String sessionPath,
  }) async {
    final dataDir = await _resolveDataDir(sessionPath);
    return LinuxWebViewSessionHandle(accountId: accountId, dataDir: dataDir);
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

class LinuxWebViewSessionHandle implements WebViewSessionHandle {
  LinuxWebViewSessionHandle({required this.accountId, required this.dataDir});

  @override
  final String accountId;

  final String dataDir;

  bool _created = false;
  bool _disposed = false;

  final _statusController =
      StreamController<AccountConnectionStatus>.broadcast();

  @override
  Stream<AccountConnectionStatus> get statusStream => _statusController.stream;

  @override
  Future<void> navigateToWhatsAppWeb() async {
    _statusController.add(AccountConnectionStatus.connecting);
    await LinuxWebKitPlatformView.create(
      viewId: accountId,
      dataDir: dataDir,
      url: AppConstants.whatsappWebUrl,
    );
    _created = true;
  }

  @override
  Future<void> reload() async {
    if (!_created) return;
    await LinuxWebKitPlatformView.reload(viewId: accountId);
  }

  @override
  Future<void> pauseRendering() async {
    if (!_created) return;
    await LinuxWebKitPlatformView.setVisible(viewId: accountId, visible: false);
  }

  @override
  Future<void> resumeRendering() async {
    if (!_created) return;
    await LinuxWebKitPlatformView.setVisible(viewId: accountId, visible: true);
  }

  @override
  Future<void> unloadFromMemory() async {
    if (_disposed || !_created) return;
    await LinuxWebKitPlatformView.destroy(viewId: accountId);
    _created = false;
  }

  @override
  Future<int?> approximateMemoryBytes() async {
    return null;
  }

  @override
  Future<void> clearSessionData() async {
    await unloadFromMemory();
    final dir = Directory(dataDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
  }

  @override
  Future<void> dispose() async {
    await unloadFromMemory();
    await _statusController.close();
  }
}
