import 'dart:io' show Platform;

import '../../domain/repositories/webview_adapter.dart';

const _kNativeCallTimeout = Duration(milliseconds: 800);
Future<T?> showOverlaySafely<T>(
  WebViewSessionHandle? activeSession,
  Future<T?> Function() showOverlay,
) async {
  final needsNativeOverlayHide = Platform.isLinux;

  if (needsNativeOverlayHide) {
    try {
      await activeSession?.pauseRendering().timeout(_kNativeCallTimeout);
    } catch (_) {}
  }

  try {
    return await showOverlay();
  } finally {
    if (needsNativeOverlayHide) {
      try {
        await activeSession?.resumeRendering().timeout(_kNativeCallTimeout);
      } catch (_) {}
    }
  }
}
