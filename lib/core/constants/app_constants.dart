import 'dart:io' show Platform;

import 'package:flutter/material.dart';

class AppConstants {
  AppConstants._();

  static const String appName = 'Multi WhatsApp Web';
  static const String whatsappWebUrl = 'https://web.whatsapp.com';

  static const int minMacOSMajorVersionForIsolation = 14;
  static const int minIOSMajorVersionForIsolation = 17;
  static const int minAndroidSdkForDataDirSuffix = 29;

  static const int maxRecommendedDesktopSessions = 5;
  static const int maxActiveWebViewsOnMobile = 1;

  static const Duration mobileBackgroundGraceForInMemoryResume = Duration(
    seconds: 30,
  );

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

enum AccountConnectionStatus {
  connecting,
  connected,
  disconnected,
  loggedOut,
  error,
}

enum FormFactor { desktop, mobile }

enum WebViewEngineKind {
  webview2,
  wkWebViewMac,
  webKitGtk,
  inAppWebViewAndroid,
  inAppWebViewIOS,
}
