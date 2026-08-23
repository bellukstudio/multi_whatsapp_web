import 'dart:io';

import 'package:logger/logger.dart';

/// Lightweight instrumentation the PRD §26 asks for but never specifies a
/// mechanism for: "10 akun: tidak crash, resource dimonitor" (desktop) and
/// "Battery impact harus diuji eksplisit" (mobile).
///
/// This does NOT attempt true per-WebView memory attribution — no public,
/// reliable cross-platform API gives that from Dart. Instead it logs
/// whole-process RSS (`ProcessInfo.currentRss`, available on the Dart VM
/// on all 5 target platforms) around the operations that are expected to
/// move memory the most: session switch, unload, and dispose. That's
/// enough to catch regressions/leaks in manual testing and CI smoke
/// tests, even without per-account granularity.
///
/// Usage pattern (see SessionCubit): call [logAround] wrapping
/// `unloadFromMemory()` / `createOrResumeSession()` calls. Over a
/// switch-back-and-forth loop (README §4 "Test dispose leak"), RSS after
/// N cycles should plateau, not grow roughly linearly with N — a growing
/// trend is the signal that a `dispose()` TODO is still unwired for that
/// platform.
class MemoryProfiler {
  MemoryProfiler._();

  static final Logger _logger = Logger(printer: SimplePrinter());

  static bool get isSupported {
    // ProcessInfo.currentRss is available on the Dart VM (desktop +
    // mobile via Flutter's embedded Dart VM); it is not meaningful on
    // Flutter web, which isn't a PRD target platform anyway (§3).
    try {
      // Touch the getter once; if it throws/is unsupported this will
      // surface immediately rather than mid-session.
      // ignore: unnecessary_statements
      ProcessInfo.currentRss;
      return true;
    } catch (_) {
      return false;
    }
  }

  static int? currentRssBytes() {
    if (!isSupported) return null;
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return null;
    }
  }

  /// Logs `label` with current RSS, in MB, e.g.
  /// `[mem] before switch->acc_123: 214 MB`
  static void log(String label) {
    final rss = currentRssBytes();
    if (rss == null) {
      _logger.d('[mem] $label: (unavailable)');
      return;
    }
    final mb = (rss / (1024 * 1024)).toStringAsFixed(1);
    _logger.d('[mem] $label: $mb MB');
  }

  /// Wraps an async operation with a before/after RSS log line, so leak
  /// regressions show up directly in the operation's log context (e.g.
  /// "unload account_123") rather than as a bare number.
  static Future<T> logAround<T>(String label, Future<T> Function() op) async {
    log('before $label');
    final result = await op();
    log('after $label');
    return result;
  }
}
