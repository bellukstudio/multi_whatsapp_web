import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:webview_windows/webview_windows.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/chat_blur_css.dart';
import '../../../../domain/repositories/webview_adapter.dart';



















class WindowsWebViewAdapter implements WebViewAdapter {
  @override
  WebViewEngineKind get engineKind => WebViewEngineKind.webview2;

  @override
  Future<IsolationProbeResult> probeIsolationSupport() async {
    return const IsolationProbeResult(
      isSupported: true,
      engine: WebViewEngineKind.webview2,
      
      
      
      
      
      
      
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
        
        
        throw WebView2RuntimeMissingException(originalError: e);
      }
      
    }

    final controller = WebviewController(environmentId: accountId);

    try {
      await controller.initialize();
    } on PlatformException catch (e) {
      
      
      
      
      
      
      
      
      
      
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
    
    
    return createOrResumeSession(accountId: accountId, sessionPath: sessionPath);
  }
}




















class WebView2RuntimeMissingException implements Exception {
  WebView2RuntimeMissingException({required this.originalError});

  final Object originalError;

  
  
  
  
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
        'https:
        '(pilih "Evergreen Bootstrapper"), lalu restart aplikasi ini.\n\n'
        'Detail teknis (sertakan ini kalau minta bantuan lebih lanjut): '
        '$detail';
  }

  @override
  String toString() => message;
}

class WindowsWebViewSessionHandle implements WebViewSessionHandle {
  WindowsWebViewSessionHandle({required this.accountId, required this.controller}) {
    
    
    
    
    
    _loadingStateSub = controller.loadingState.listen((state) {
      if (state == LoadingState.navigationCompleted && _lastCss != null) {
        _injectCurrentCss();
      }
    });
  }

  @override
  final String accountId;
  final WebviewController controller;

  final _statusController =
  StreamController<AccountConnectionStatus>.broadcast();

  bool _disposed = false;
  String? _lastCss;
  StreamSubscription<LoadingState>? _loadingStateSub;

  @override
  Stream<AccountConnectionStatus> get statusStream => _statusController.stream;

  @override
  Future<void> navigateToWhatsAppWeb() async {
    _statusController.add(AccountConnectionStatus.connecting);
    await controller.loadUrl(AppConstants.whatsappWebUrl);
    
    
    
    
    
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
  bool get supportsChatBlur => true;

  @override
  Future<void> setChatBlurCss(String? css) async {
    _lastCss = css;
    if (_disposed) return;
    await _injectCurrentCss();
  }

  Future<void> _injectCurrentCss() async {
    if (_disposed) return;
    try {
      await controller.executeScript(
        buildChatBlurInjectionScript(_lastCss ?? ''),
      );
    } catch (_) {
      
      
      
    }
  }

  @override
  Future<void> dispose() async {
    await _loadingStateSub?.cancel();
    await unloadFromMemory();
    await _statusController.close();
  }
}