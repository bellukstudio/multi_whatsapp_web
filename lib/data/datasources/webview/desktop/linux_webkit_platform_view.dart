import 'package:flutter/services.dart';

class LinuxWebKitPlatformView {
  static const _channel = MethodChannel('multi_whatsapp_web/webkit_view');

  static Future<void> create({
    required String viewId,
    required String dataDir,
    required String url,
  }) {
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

  static Future<void> destroy({required String viewId}) {
    return _channel.invokeMethod('destroy', {'viewId': viewId});
  }
}
