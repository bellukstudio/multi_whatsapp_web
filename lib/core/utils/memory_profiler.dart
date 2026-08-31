import 'dart:io';

import 'package:logger/logger.dart';

class MemoryProfiler {
  MemoryProfiler._();

  static final Logger _logger = Logger(printer: SimplePrinter());

  static bool get isSupported {
    try {
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

  static void log(String label) {
    final rss = currentRssBytes();
    if (rss == null) {
      _logger.d('[mem] $label: (unavailable)');
      return;
    }
    final mb = (rss / (1024 * 1024)).toStringAsFixed(1);
    _logger.d('[mem] $label: $mb MB');
  }

  static Future<T> logAround<T>(String label, Future<T> Function() op) async {
    log('before $label');
    final result = await op();
    log('after $label');
    return result;
  }
}
