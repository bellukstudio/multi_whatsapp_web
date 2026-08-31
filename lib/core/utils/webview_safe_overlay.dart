// core/utils/webview_safe_overlay.dart
import '../../domain/repositories/webview_adapter.dart';

/// PRD §24 catatan: webview_win_floating (Windows) dan native
/// WebKitGTK overlay (Linux) sama-sama menempatkan native view DI ATAS
/// surface Flutter — dialog/menu Flutter tidak bisa tampil di atasnya
/// selama native view itu visible. Wrapper ini memakai ulang
/// pauseRendering()/resumeRendering() (awalnya untuk PRD §27) untuk
/// menyembunyikan native view sementara selama overlay Flutter tampil.
const _kNativeCallTimeout = Duration(milliseconds: 800);
Future<T?> showOverlaySafely<T>(
  WebViewSessionHandle? activeSession,
  Future<T?> Function() showOverlay,
) async {
  try {
    await activeSession?.pauseRendering().timeout(_kNativeCallTimeout);
  } catch (_) {
    // Covers BOTH: (a) the native WebView rejecting pause/resume while
    // it's being torn down/reloaded (original comment's case), and now
    // also (b) TimeoutException from the .timeout() above when the
    // native call hangs instead of erroring. Either way, keep going —
    // never let this block the Flutter overlay from showing.
  }
 
  try {
    return await showOverlay();
  } finally {
    try {
      await activeSession?.resumeRendering().timeout(_kNativeCallTimeout);
    } catch (_) {
      // Likewise, a canceled/resumed/hung WebView operation should never
      // block the overlay dismissal flow.
    }
  }
}