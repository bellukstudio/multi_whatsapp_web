import 'package:flutter/services.dart';

/// Thin wrapper around the `multi_whatsapp_web/webkit_view` method
/// channel implemented natively in `linux/webkit_multi_view_plugin.cc`.
///
/// Each method maps 1:1 to a native GTK operation on a `WebKitWebView`
/// living in the `GtkFixed` overlay layer set up in
/// `linux/runner/my_application.cc`. There is deliberately no
/// JS-bridge/navigation-delegate surface here — only what
/// [LinuxWebViewSessionHandle] actually needs.
class LinuxWebKitPlatformView {
  static const _channel = MethodChannel('multi_whatsapp_web/webkit_view');

  /// Creates (or, if [viewId] already exists natively, just re-navigates)
  /// a `WebKitWebView` whose cookies/localStorage/IndexedDB/etc. are
  /// rooted at [dataDir] — a distinct on-disk directory per account,
  /// which is the actual isolation boundary (PRD §24/§25).
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

  /// Moves/resizes the native view to the given rect, in the same
  /// logical-pixel coordinate space Flutter's own `RenderBox` reports
  /// (see `_LinuxEngineSurface` in `webview_container.dart`, which calls
  /// this every frame so the native view tracks Flutter's layout).
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