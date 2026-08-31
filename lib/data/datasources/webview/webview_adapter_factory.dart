import 'dart:io' show Platform;

import '../../../domain/repositories/webview_adapter.dart';
import 'desktop/windows_webview_adapter.dart';
import 'desktop/macos_webview_adapter.dart';
import 'desktop/linux_webview_adapter.dart';
import 'mobile/android_webview_adapter.dart';
import 'mobile/ios_webview_adapter.dart';

class WebViewAdapterFactory {
  static WebViewAdapter create() {
    if (Platform.isWindows) return WindowsWebViewAdapter();
    if (Platform.isMacOS) return MacOSWebViewAdapter();
    if (Platform.isLinux) return LinuxWebViewAdapter();
    if (Platform.isAndroid) return AndroidWebViewAdapter();
    // if (Platform.isIOS) return IOSWebViewAdapter();
    throw UnsupportedError(
      'Multi WhatsApp Web does not target this platform (PRD §3).',
    );
  }
}
