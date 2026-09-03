import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:webview_windows/webview_windows.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/repositories/webview_adapter.dart';

/// PRD §24 row 1 — Windows / WebView2 via `webview_flutter_windows`
/// (maintained fork of the unmaintained `webview_windows` — see migration
/// note at the bottom of this file for why we moved off it).
///
/// Isolation mechanism: `WebviewController.initializeEnvironment(
/// userDataPath: ...)` — see IMPORTANT CAVEAT below, this is NOT the same
/// guarantee as a fully separate WebView2 environment per account.
///
/// RAM wiring (§26/§27): [WindowsWebViewSessionHandle.unloadFromMemory]
/// calls `WebviewController.dispose()`, which releases this controller's
/// reference on the (ref-counted, shared) WebView2 environment. The
/// environment/process itself is only actually torn down once EVERY
/// controller sharing it has been disposed — see caveat below for why
/// this matters for multi-account memory accounting.
/// [pauseRendering] avoids the full teardown cost for sessions kept warm
/// by [SessionPoolManager] but temporarily out of view, by signalling
/// page visibility so WhatsApp Web's own background-tab JS throttling
/// engages.
class WindowsWebViewAdapter implements WebViewAdapter {
  @override
  WebViewEngineKind get engineKind => WebViewEngineKind.webview2;

  @override
  Future<IsolationProbeResult> probeIsolationSupport() async {
    return const IsolationProbeResult(
      isSupported: true,
      engine: WebViewEngineKind.webview2,
      // Genuine per-account isolation, including when multiple accounts
      // are kept warm concurrently: the patched `flutter-webview-windows`
      // plugin gives each `environmentId` (== accountId) its own
      // `ICoreWebView2Environment`/userDataPath, so several accounts'
      // environments can be alive in this process at the same time
      // without sharing cookies/localStorage. See
      // webview_windows_plugin.cc's `webview_hosts_` map.
      isNativeIsolation: true,
      reason:
      'Each account gets its own ICoreWebView2Environment (own '
          'userDataPath), created via a distinct environmentId, and these '
          'environments can coexist in the same process — not limited to '
          'one account open at a time.',
    );
  }

  @override
  Future<WebViewSessionHandle> createOrResumeSession({
    required String accountId,
    required String sessionPath,
    String? accountName,
  }) async {
    // MULTI-ENVIRONMENT (patched `flutter-webview-windows`): each
    // account now gets its OWN `environmentId` (== accountId), which the
    // native plugin maps to its own independent `ICoreWebView2Environment`
    // (own `userDataPath`/profile). Unlike the old single-shared-
    // environment design, several accounts' environments can now be
    // alive AT THE SAME TIME — SessionPoolManager no longer needs to be
    // capped to maxWarmSessions=1 on Windows, and switching between
    // already-warm accounts no longer requires tearing the previous one
    // down first (that's what used to show up as "reload tiap pindah
    // akun"). See webview_windows_plugin.cc's `webview_hosts_` map.
    //
    // `initializeEnvironment` for a given environmentId only needs to
    // succeed ONCE per account for the life of the process — if this
    // account's environment is already alive (e.g. we're re-entering an
    // account that's still warm somewhere), the plugin returns
    // `environment_already_initialized` for that id specifically, which
    // we treat as "nothing to do" rather than an error.
    try {
      await WebviewController.initializeEnvironment(
        userDataPath: sessionPath,
        environmentId: accountId,
      );
    } on PlatformException catch (e) {
      final detail = e.toString().toLowerCase();
      final alreadyInitializedForThisAccount =
          detail.contains('environment') &&
              (detail.contains('already') || detail.contains('alive'));
      if (!alreadyInitializedForThisAccount) {
        // Genuinely missing WebView2 Runtime or some other native
        // failure — surface immediately.
        throw WebView2RuntimeMissingException(originalError: e);
      }
      // This account's own environment is already up — fine, reuse it.
    }

    final controller = WebviewController(environmentId: accountId);

    try {
      await controller.initialize();
    } on PlatformException catch (e) {
      // webview_flutter_windows hardens the native COM/DispatcherQueue
      // layer that caused most of the `unsupported_platform` /
      // "Creating DispatcherQueueController failed." failures we used to
      // see with upstream `webview_windows` (see
      // WebView2RuntimeMissingException doc below for the history). A
      // short retry is kept here only as a defensive fallback for
      // genuine transient races (e.g. WebView2 Runtime not fully ready
      // immediately after process start) — not as a workaround for a
      // permanently orphaned native DispatcherQueue, which this package
      // should no longer produce.
      const retryDelays = [Duration(milliseconds: 300), Duration(milliseconds: 800)];

      Object? lastError = e;
      for (final delay in retryDelays) {
        await Future<void>.delayed(delay);
        try {
          await controller.initialize();
          lastError = null;
          break;
        } catch (retryError) {
          lastError = retryError;
        }
      }

      if (lastError != null) {
        throw WebView2RuntimeMissingException(originalError: lastError);
      }
    }

    await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

    return WindowsWebViewSessionHandle(accountId: accountId, controller: controller);
  }

  @override
  Future<WebViewSessionHandle> reloadFromPersistedStorage({
    required String accountId,
    required String sessionPath,
    String? accountName,
  }) {
    // Desktop processes are long-lived (PRD §14a: "koneksi tetap hidup"),
    // so on Windows a "reload after resume" is just a normal (re)create.
    return createOrResumeSession(accountId: accountId, sessionPath: sessionPath);
  }
}

/// Dilempar saat WebView2 environment/controller gagal dibuat setelah
/// retry. [SessionCubit]/[WebViewContainer] menampilkan [message] ini
/// langsung ke pengguna alih-alih pesan `PlatformException` mentah yang
/// membingungkan.
///
/// MIGRATION NOTE: sebelumnya kita pakai `webview_windows` (upstream
/// `jnschulze/flutter-webview-windows`, sudah tidak aktif dikembangkan).
/// Package itu punya bug lama di helper native-nya (`RoHelper`) seputar
/// `CreateDispatcherQueueController` — cache-nya salah (raw pointer ke
/// stack milik caller, bisa dangling), dan di beberapa build kami juga
/// menemukan error native `RPC_E_WRONG_THREAD` (0x8001010E) yang
/// dokumentasi Microsoft artikan sebagai "sudah ada DispatcherQueue di
/// thread ini" — kemungkinan bentrok dengan compositor Impeller/ANGLE
/// milik Flutter sendiri di thread yang sama. Alih-alih terus menambal
/// fork yang sudah tidak terawat, kita pindah ke `webview_flutter_windows`
/// (fork aktif oleh omar-hanafy) yang sudah "hardens the native COM and
/// channel layers". [isDispatcherQueueConflict] tetap dipertahankan
/// sebagai pengaman kalau-kalau gejala serupa masih muncul, tapi
/// seharusnya sudah jauh lebih jarang (atau tidak pernah) terjadi lagi.
class WebView2RuntimeMissingException implements Exception {
  WebView2RuntimeMissingException({required this.originalError});

  final Object originalError;

  /// True kalau kegagalan ini masih terlihat seperti konflik
  /// DispatcherQueue/COM tingkat native. UI (lihat `_ErrorState` di
  /// webview_container.dart) pakai ini untuk memutuskan apakah
  /// menampilkan tombol "Restart Aplikasi".
  bool get isDispatcherQueueConflict {
    final detail = originalError.toString().toLowerCase();
    return detail.contains('dispatcherqueue') ||
        detail.contains('unsupported_platform') ||
        detail.contains('platform is not supported') ||
        detail.contains('0x8001010e') ||
        detail.contains('wrong_thread');
  }

  String get message {
    final detail = originalError.toString();
    final lower = detail.toLowerCase();

    final String likelyCause;
    if (lower.contains('access is denied') ||
        lower.contains('access_denied') ||
        lower.contains('0x80070005')) {
      likelyCause =
      'Kemungkinan besar: aplikasi tidak punya izin tulis di folder '
          'tempat ia dijalankan (WebView2 perlu membuat folder data di '
          'sana). Coba jalankan dari folder biasa seperti Documents/Desktop, '
          'bukan Program Files atau network drive.';
    } else if (lower.contains('in use') ||
        lower.contains('being used by another process') ||
        lower.contains('sharing violation')) {
      likelyCause =
      'Kemungkinan besar: folder data WebView2 sedang terkunci — '
          'mungkin dari proses sebelumnya yang belum benar-benar tertutup. '
          'Tutup semua proses aplikasi ini lewat Task Manager, hapus folder '
          'data WebView2 di sebelah file .exe, lalu coba lagi.';
    } else if (lower.contains('policy') || lower.contains('disabled')) {
      likelyCause =
      'Kemungkinan besar: WebView2 dinonaktifkan lewat kebijakan '
          '(Group Policy) di perangkat ini — umum terjadi di laptop '
          'kantor/instansi yang dikelola IT. Perlu izin admin IT untuk '
          'mengaktifkannya kembali.';
    } else if (lower.contains('environment_creation_failed')) {
      likelyCause =
      'WebView2 Runtime kemungkinan belum terpasang atau rusak di '
          'perangkat ini (ini kode error resmi package untuk kasus itu).';
    } else if (isDispatcherQueueConflict) {
      likelyCause =
      'Kemungkinan konflik level native antara komponen rendering '
          'Windows di proses ini — coba restart total aplikasi (bukan '
          'cuma switch akun). Kalau ini terus terjadi walau sudah pakai '
          'webview_flutter_windows, ini kemungkinan bug baru yang perlu '
          'dilaporkan ke repo package tersebut.';
    } else {
      likelyCause =
      'Kemungkinan: WebView2 Runtime benar-benar belum terpasang atau '
          'rusak di perangkat ini.';
    }

    return '$likelyCause\n\n'
        'Kalau sudah terpasang tapi tetap gagal, install ulang dari: '
        'https://developer.microsoft.com/en-us/microsoft-edge/webview2/ '
        '(pilih "Evergreen Bootstrapper"), lalu restart aplikasi ini.\n\n'
        'Detail teknis (sertakan ini kalau minta bantuan lebih lanjut): '
        '$detail';
  }

  @override
  String toString() => message;
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
    // watching WhatsApp Web's DOM (e.g. presence of the QR canvas vs. the
    // chat list) to emit connecting/connected/disconnected accurately —
    // WhatsApp Web has no public JS status API.
  }

  @override
  Future<void> reload() => controller.reload();

  @override
  Future<void> pauseRendering() async {
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
    await controller.dispose();
    _disposed = true;
  }

  @override
  Future<int?> approximateMemoryBytes() async {
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