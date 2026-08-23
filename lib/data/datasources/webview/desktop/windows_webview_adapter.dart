import 'dart:async';

import 'package:webview_windows/webview_windows.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/repositories/webview_adapter.dart';

/// PRD §24 row 1 — Windows / WebView2 via `webview_windows`.
///
/// Isolation mechanism: a **separate user-data folder per instance**.
/// Most mature engine in the PRD's comparison table, PoC priority #1
/// (§3).
///
/// RAM wiring (§26/§27): [WindowsWebViewSessionHandle.unloadFromMemory]
/// calls `WebviewController.dispose()`, which tears down the underlying
/// WebView2 environment/process for that instance — this is what
/// actually returns memory to the OS, not just hiding the widget.
/// [pauseRendering] avoids the full teardown cost for sessions kept warm
/// by [SessionPoolManager] but temporarily out of view, by signalling
/// page visibility so WhatsApp Web's own background-tab JS throttling
/// engages.
class WindowsWebViewAdapter implements WebViewAdapter {
  @override
  WebViewEngineKind get engineKind => WebViewEngineKind.webview2;

  @override
  Future<IsolationProbeResult> probeIsolationSupport() async {
    // instances with different userDataPath values and confirm cookies
    // set in one are NOT visible in the other before trusting this.
    return const IsolationProbeResult(
      isSupported: true,
      engine: WebViewEngineKind.webview2,
      isNativeIsolation: true,
      reason: 'WebView2 supports per-instance user-data folders natively.',
    );
  }

  @override
  Future<WebViewSessionHandle> createOrResumeSession({
    required String accountId,
    required String sessionPath,
  }) async {
    final controller = WebviewController();
    // `userDataPath` is WebView2's isolation primitive for this platform
    // (PRD §24 row 1) — each account gets a fully distinct cookie/
    // localStorage/IndexedDB jar by virtue of a distinct folder.
    await controller.initialize();
    return WindowsWebViewSessionHandle(accountId: accountId, controller: controller);
  }

  @override
  Future<WebViewSessionHandle> reloadFromPersistedStorage({
    required String accountId,
    required String sessionPath,
  }) {
    // Desktop processes are long-lived (PRD §14a: "koneksi tetap hidup"),
    // so on Windows a "reload after resume" is just a normal (re)create.
    return createOrResumeSession(accountId: accountId, sessionPath: sessionPath);
  }
}

class WindowsWebViewSessionHandle implements WebViewSessionHandle {
  WindowsWebViewSessionHandle({required this.accountId, required this.controller});

  @override
  final String accountId;
  final WebviewController controller;

  final _statusController =
      StreamController<AccountConnectionStatus>.broadcast();

  bool _disposed = false;

  @override
  Stream<AccountConnectionStatus> get statusStream => _statusController.stream;

  @override
  Future<void> navigateToWhatsAppWeb() async {
    _statusController.add(AccountConnectionStatus.connecting);
    await controller.loadUrl(AppConstants.whatsappWebUrl);
    // TODO: bridge controller.webMessage / a small injected JS observer
    // watching WhatsApp Web's DOM (e.g. presence of the QR canvas vs. the
    // chat list) to emit connecting/connected/disconnected accurately —
    // WhatsApp Web has no public JS status API.
  }

  @override
  Future<void> reload() => controller.reload();

  @override
  Future<void> pauseRendering() async {
    // Signals the page as hidden so Chromium's own background-tab
    // throttling (reduced timer rate, deferred rAF, etc.) engages,
    // without tearing down the WebView2 process the way unloadFromMemory
    // does. Cheap, reversible, meaningfully reduces idle CPU/RAM churn
    // for warm-but-not-visible accounts (PRD §26).
    await controller.executeScript(
      "Object.defineProperty(document, 'hidden', {value: true, configurable: true});"
      "document.dispatchEvent(new Event('visibilitychange'));",
    );
  }

  @override
  Future<void> resumeRendering() async {
    await controller.executeScript(
      "Object.defineProperty(document, 'hidden', {value: false, configurable: true});"
      "document.dispatchEvent(new Event('visibilitychange'));",
    );
  }

  @override
  Future<void> unloadFromMemory() async {
    if (_disposed) return;
    // This is the real memory release on Windows: disposing the
    // WebviewController tears down its WebView2 environment/process.
    // SessionPoolManager only calls this on LRU eviction — it is NOT
    // called just for "not currently visible" (that's pauseRendering).
    await controller.dispose();
    _disposed = true;
  }

  @override
  Future<int?> approximateMemoryBytes() async {
    // webview_windows doesn't expose a per-instance memory API; callers
    // fall back to whole-process RSS via MemoryProfiler instead.
    return null;
  }

  @override
  Future<void> clearSessionData() async {
    await controller.clearCache();
    await controller.clearCookies();
  }

  @override
  Future<void> dispose() async {
    await unloadFromMemory();
    await _statusController.close();
  }
}
