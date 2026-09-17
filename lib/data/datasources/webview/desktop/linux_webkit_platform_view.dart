import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// File yang di-drag-and-drop dari luar aplikasi (mis. file manager) ke
/// atas WebKitWebView milik [viewId], ditangkap secara native di
/// linux/runner/webkit_multi_view_plugin.cc (lihat komentar
/// "Drag & drop file dari luar aplikasi" di sana untuk alasan kenapa ini
/// tidak bisa lewat DropTarget Flutter biasa di Linux) dan diteruskan ke
/// sini lewat method channel.
class LinuxFileDropEvent {
  const LinuxFileDropEvent({required this.viewId, required this.paths});

  final String viewId;
  final List<String> paths;
}

class LinuxWebKitPlatformView {
  static const _channel = MethodChannel('multiwhatsappweb/webkit_view');

  static final _dropController =
      StreamController<LinuxFileDropEvent>.broadcast();
  static final _dragEnteredController = StreamController<String>.broadcast();
  static final _dragExitedController = StreamController<String>.broadcast();

  /// Emits setiap kali file di-drop di atas salah satu WebKitWebView.
  /// Widget yang menampilkan sebuah viewId tertentu memfilter sendiri
  /// lewat `event.viewId == accountId`.
  static Stream<LinuxFileDropEvent> get onFilesDropped => _dropController.stream;

  /// Emits viewId setiap kali drag masuk ke area WebKitWebView tersebut
  /// (dikirim tiap tick drag-motion oleh sisi native — lihat OnDragMotion
  /// di webkit_multi_view_plugin.cc — jadi bisa muncul berulang selama
  /// hover, bukan cuma sekali).
  static Stream<String> get onDragEntered => _dragEnteredController.stream;

  /// Emits viewId saat drag meninggalkan area WebKitWebView tersebut.
  static Stream<String> get onDragExited => _dragExitedController.stream;

  static bool _handlerInstalled = false;

  static void _ensureHandlerInstalled() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      switch (call.method) {
        case 'filesDropped':
          if (args is Map) {
            final viewId = args['viewId'] as String?;
            final rawPaths = args['paths'];
            if (viewId != null && rawPaths is List) {
              _dropController.add(
                LinuxFileDropEvent(
                  viewId: viewId,
                  paths: rawPaths.whereType<String>().toList(),
                ),
              );
            }
          }
          break;
        case 'dragEntered':
          if (args is Map && args['viewId'] is String) {
            _dragEnteredController.add(args['viewId'] as String);
          }
          break;
        case 'dragExited':
          if (args is Map && args['viewId'] is String) {
            _dragExitedController.add(args['viewId'] as String);
          }
          break;
      }
      return null;
    });
  }

  static Future<void> create({
    required String viewId,
    required String dataDir,
    required String url,
  }) {
    _ensureHandlerInstalled();
    return _channel.invokeMethod('create', {
      'viewId': viewId,
      'dataDir': dataDir,
      'url': url,
    });
  }

  static Future<void> setGeometry({
    required String viewId,
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    return _channel.invokeMethod('setGeometry', {
      'viewId': viewId,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    });
  }

  static Future<void> setVisible({
    required String viewId,
    required bool visible,
  }) {
    return _channel.invokeMethod('setVisible', {
      'viewId': viewId,
      'visible': visible,
    });
  }

  static Future<void> reload({required String viewId}) {
    return _channel.invokeMethod('reload', {'viewId': viewId});
  }

  /// FIX: sisi native dulu selalu mengembalikan null (fire-and-forget) —
  /// sekarang mengembalikan hasil evaluasi JS yang sesungguhnya, dikirim
  /// sebagai string JSON (lihat OnJsEvalFinished di
  /// webkit_multi_view_plugin.cc). Di-decode di sini supaya nilai baliknya
  /// berbentuk sama (Map/List/num/bool/null) seperti yang sudah dipakai
  /// untuk hasil `controller.executeScript` di Windows.
  static Future<dynamic> runJavaScript({
    required String viewId,
    required String script,
  }) async {
    final result = await _channel.invokeMethod<dynamic>('runJavaScript', {
      'viewId': viewId,
      'script': script,
    });
    if (result is String) {
      try {
        return jsonDecode(result);
      } catch (_) {
        return result;
      }
    }
    return result;
  }

  static Future<void> destroy({required String viewId}) {
    return _channel.invokeMethod('destroy', {'viewId': viewId});
  }
}