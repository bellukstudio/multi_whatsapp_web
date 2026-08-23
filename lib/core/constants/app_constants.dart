import 'dart:io' show Platform;

import 'package:flutter/material.dart';

/// Global constants for the app. Keeping these centralized makes it easy to
/// audit against PRD requirements (e.g. §24 minimum OS versions, §26
/// performance targets).
class AppConstants {
  AppConstants._();

  static const String appName = 'Multi WhatsApp Web';
  static const String whatsappWebUrl = 'https://web.whatsapp.com';

  /// PRD §24 — minimum OS versions required for *native* persistent,
  /// isolated WebView profiles. Below these versions, isolation must fall
  /// back to manual cookie management (more complex, more bug-prone) or the
  /// platform should be considered "PoC failed" per §24 point 3.
  static const int minMacOSMajorVersionForIsolation = 14;
  static const int minIOSMajorVersionForIsolation = 17;
  static const int minAndroidSdkForDataDirSuffix = 29; // Android 10 (API 29)

  /// PRD §26 — desktop can reasonably keep multiple sessions "warm" at once;
  /// mobile must keep only one session fully active at a time (§27).
  static const int maxRecommendedDesktopSessions = 10;
  static const int maxActiveWebViewsOnMobile = 1;

  /// PRD §11 — used to decide whether a resumed mobile app can trust
  /// in-memory state or must reload from persisted storage.
  static const Duration mobileBackgroundGraceForInMemoryResume =
      Duration(seconds: 30);

  static Icon settingsIcon({double? size, Color? color}) {
    if (Platform.isWindows) {
      return Icon(Icons.settings_rounded, size: size, color: color);
    }
    if (Platform.isLinux) {
      return Icon(Icons.tune_rounded, size: size, color: color);
    }
    return Icon(Icons.settings_outlined, size: size, color: color);
  }
}

/// PRD §9 — account lifecycle states. Kept as an enum (not free-text
/// strings) so the domain layer stays strongly typed across platforms.
enum AccountConnectionStatus {
  connecting,
  connected,
  disconnected,
  loggedOut,
  error,
}

/// Which physical form factor is currently rendering the UI. Used only by
/// the presentation layer (PRD §6.1 vs §6.2) — never leaks into domain/data.
enum FormFactor { desktop, mobile }

/// Which native WebView engine backs a given platform (PRD §24 table).
enum WebViewEngineKind {
  webview2, // Windows
  wkWebViewMac, // macOS
  webKitGtk, // Linux
  inAppWebViewAndroid, // Android
  inAppWebViewIOS, // iOS
}
