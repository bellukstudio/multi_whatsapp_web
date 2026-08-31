import 'dart:io' show Platform;

import '../../../domain/repositories/webview_adapter.dart';
import 'desktop/windows_webview_adapter.dart';
import 'desktop/macos_webview_adapter.dart';
import 'desktop/linux_webview_adapter.dart';
import 'mobile/android_webview_adapter.dart';
import 'mobile/ios_webview_adapter.dart';

/// Picks the correct [WebViewAdapter] implementation at runtime.
///
/// PRD §10: this is the ONE place that is allowed to know "which OS am I
/// on" for WebView purposes. Everything above this (domain, bloc, UI)
/// only ever sees the [WebViewAdapter] interface.
///
/// PRD §3 rollout order: Windows -> Android -> Linux -> macOS -> iOS.
/// Android/iOS now run on `webview_flutter` instead of
/// `flutter_inappwebview` — see `mobile/mobile_webview_session_handle.dart`
/// for why, and its TODO ISOLATION note before relying on multi-account
/// separation on mobile.
class WebViewAdapterFactory {
  static WebViewAdapter create() {
    if (Platform.isWindows) return WindowsWebViewAdapter();
    if (Platform.isMacOS) return MacOSWebViewAdapter();
    if (Platform.isLinux) return LinuxWebViewAdapter();
    if (Platform.isAndroid) return AndroidWebViewAdapter();
    if (Platform.isIOS) return IOSWebViewAdapter();
    throw UnsupportedError(
      'Multi WhatsApp Web does not target this platform (PRD §3).',
    );
  }
}