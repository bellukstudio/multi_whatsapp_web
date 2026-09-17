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

  // ---------------------------------------------------------------------
  // Memory watchdog (Linux / WebKitGTK only)
  // ---------------------------------------------------------------------
  //
  // "Unable to shrink memory footprint of process (628 MB) below the kill
  // thresold (600 MB). Killed" is printed by WebKit itself — WTF's
  // MemoryPressureHandler, running INSIDE each WebKitWebProcess. When that
  // one process passes its kill threshold WebKit first tries
  // releaseMemory(Critical::Yes) and, if the footprint is still over, kills
  // that web process. The Flutter app is never the thing being killed; the
  // account's page dies and comes back blank/reloading, which is exactly the
  // "web restarts over and over" symptom.
  //
  // Two consequences that the budgets below are built around:
  //
  //   * The 600 MB is PER WEB PROCESS, not for the app or the process tree.
  //     Comparing a summed tree figure (1.4 GB across 5 processes) against
  //     it puts the pool permanently in panic mode — which is what caused
  //     the reload loop.
  //   * Nothing in Dart can rescue a web process that is already over the
  //     line. WebKit has already tried harder than we can, and the logs show
  //     reload() moving the number by 0.1 MB. The fix for the kill itself
  //     belongs in the WebKitGTK configuration (see
  //     linux/runner/webkit_multi_view_plugin.cc).
  //
  // So the Dart side now does only what it is actually able to do: free
  // whole background accounts when the MACHINE is running short of memory.
  // On Windows (WebView2) there is no such kill and no watchdog at all —
  // the pool behaves exactly as it did before this change.
  static bool get memoryWatchdogEnabled => Platform.isLinux;

  /// Mirrors the per-web-process kill threshold WebKit is configured with,
  /// used only for logging/diagnostics so the app can point at the account
  /// that is about to be killed instead of guessing after the fact.
  /// Mirrors WEB_PROCESS_MEMORY_LIMIT_MB in
  /// linux/runner/webkit_multi_view_plugin.cc — keep these two in sync if
  /// you change one. Used only for logging/diagnostics here; the actual
  /// kill is enforced natively.
  static int get webProcessKillThresholdBytes =>
      _envMb('MWW_MEM_KILL_MB') ?? 900 * 1024 * 1024;

  /// Warn (and start freeing background accounts) once any single web
  /// process reaches this share of the kill threshold.
  static const double webProcessWarnRatio = 0.85;

  /// Free background accounts when the machine has less than this share of
  /// its RAM available (MemAvailable/MemTotal from /proc/meminfo). This is a
  /// real signal, unlike a fixed MB budget, and it is false on an idle 16 GB
  /// desktop — which is the point: no action, no reload loop.
  static const double systemLowMemoryRatio = 0.15;

  static const Duration memoryPollInterval = Duration(seconds: 30);

  /// Freed pages don't leave the accounting the instant a process dies.
  static const Duration memorySettleDelay = Duration(seconds: 2);

  /// Under pressure, background accounts are dropped this fast instead of
  /// waiting out the full idle-eviction timeout.
  static const Duration pressureIdleGrace = Duration(seconds: 20);

  /// Hard floor between two rounds of pressure relief. Without this the
  /// watchdog can re-fire on every poll and thrash the pool.
  static const Duration pressureCooldown = Duration(minutes: 2);

  static int? _envMb(String key) {
    final raw = Platform.environment[key];
    if (raw == null) return null;
    final mb = int.tryParse(raw.trim());
    if (mb == null || mb <= 0) return null;
    return mb * 1024 * 1024;
  }

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