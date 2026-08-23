// core/utils/webview_safe_overlay.dart
import '../../domain/repositories/webview_adapter.dart';

/// PRD §24 catatan: webview_win_floating (Windows) dan native
/// WebKitGTK overlay (Linux) sama-sama menempatkan native view DI ATAS
/// surface Flutter — dialog/menu Flutter tidak bisa tampil di atasnya
/// selama native view itu visible. Wrapper ini memakai ulang
/// pauseRendering()/resumeRendering() (awalnya untuk PRD §27) untuk
/// menyembunyikan native view sementara selama overlay Flutter tampil.
Future<T?> showOverlaySafely<T>(
  WebViewSessionHandle? activeSession,
  Future<T?> Function() showOverlay,
) async {
  try {
    await activeSession?.pauseRendering();
  } catch (_) {
    // The native WebView can reject pause/resume while it is being torn
    // down or reloaded (common on desktop during a menu/dialog transition).
    // Keep the Flutter overlay open instead of crashing the whole app.
  }

  try {
    return await showOverlay();
  } finally {
    try {
      await activeSession?.resumeRendering();
    } catch (_) {
      // Likewise, a canceled/resumed WebView operation should never block the
      // overlay dismissal flow.
    }
  }
}
