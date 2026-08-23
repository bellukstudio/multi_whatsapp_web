import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/repositories/webview_adapter.dart';
import 'linux_webkit_platform_view.dart';

/// PRD §24 row 3 — Linux.
///
/// History: three passes of this file so far —
/// 1. Misused `package:webview_windows` (Windows-only) on Linux, which
///    threw immediately.
/// 2. `package:webview_cef` — worked, but ran ONE global CEF process
///    with a single shared cookie store, so two accounts collided as
///    WhatsApp Web's "use here" conflict prompt.
/// 3. A separate system Chromium/Chrome process per account (real
///    isolation via `--user-data-dir`, but each account opened as its
///    own OS window instead of embedding in the app).
///
/// This pass replaces (3) with genuine embedding: each account gets a
/// native `WebKitWebView` (GTK/WebKitGTK, NOT a Flutter package) living
/// in a `GtkFixed` layer stacked on top of the Flutter `FlView` (see
/// `linux/runner/my_application.cc`), positioned every frame to match
/// wherever `_LinuxEngineSurface` (in `webview_container.dart`) is laid
/// out in the Flutter widget tree. Isolation is real: each WebKitWebView
/// gets its own `WebKitWebsiteDataManager` rooted at a distinct
/// directory (== [Account.sessionPath], resolved to an absolute
/// app-support path) — see `linux/webkit_multi_view_plugin.cc`.
///
/// Requires: `webkit2gtk-4.1` (or `-4.0`) installed, and the native
/// runner changes in `linux/` actually built — see that folder's files
/// for what needs adding to `linux/CMakeLists.txt` /
/// `linux/runner/CMakeLists.txt`. This native surface is NOT something
/// that's been compiled/tested in this environment (no Flutter/GTK
/// toolchain available here) — treat it as a first pass to build and
/// debug locally, not a verified-working implementation.
class LinuxWebViewAdapter implements WebViewAdapter {
  @override
  WebViewEngineKind get engineKind => WebViewEngineKind.webKitGtk;

  @override
  Future<IsolationProbeResult> probeIsolationSupport() async {
    return const IsolationProbeResult(
      isSupported: false,
      engine: WebViewEngineKind.webKitGtk,
      isNativeIsolation: true,
      reason: 'Each account gets its own WebKitWebView backed by a '
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
    // Desktop processes are long-lived (PRD §14a) — a "reload after
    // resume" is just a normal (re)create, same as the other adapters.
    return createOrResumeSession(accountId: accountId, sessionPath: sessionPath);
  }
}

class LinuxWebViewSessionHandle implements WebViewSessionHandle {
  LinuxWebViewSessionHandle({required this.accountId, required this.dataDir});

  @override
  final String accountId;

  /// Absolute path passed as the native `WebKitWebsiteDataManager`'s
  /// base-data/cache directory — this IS the isolation boundary
  /// (§24/§25), same role `--user-data-dir` played in the previous
  /// external-process adapter.
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
    // TODO: same limitation as every other adapter pass — WhatsApp Web
    // has no public JS status API. Unlike the external-process adapter,
    // we DO have a real JS-execution channel available in principle
    // (webkit_web_view_run_javascript), so a DOM observer for QR-canvas
    // vs. chat-list presence is more feasible here than it was for the
    // external-process approach — just not wired up yet.
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
    // Unlike the external-process adapter, all WebKitWebViews now share
    // this app's single OS process — there's no separate PID to read
    // /proc/<pid>/status for. Per-account RAM isn't cheaply separable
    // this way; falls back to null (whole-app RSS via MemoryProfiler,
    // same as the Windows/mobile adapters).
    return null;
  }

  @override
  Future<void> clearSessionData() async {
    // Genuinely possible here (distinct dataDir per account): destroy
    // the native view first, then wipe its on-disk profile.
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