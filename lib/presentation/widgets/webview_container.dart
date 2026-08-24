import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_windows/webview_windows.dart' as win;

import '../../data/datasources/webview/desktop/linux_webview_adapter.dart';
import '../../data/datasources/webview/desktop/linux_webkit_platform_view.dart';
import '../../data/datasources/webview/desktop/windows_webview_adapter.dart';
import '../../data/datasources/webview/mobile/mobile_webview_session_handle.dart';
import '../../domain/entities/account.dart';
import '../bloc/session/session_cubit.dart';

/// Renders the real per-platform WebView widget bound to
/// `sessionState.handle`. This is the ONLY widget in the app that
/// imports `webview_windows` / `flutter_inappwebview` directly — every
/// other widget only sees [SessionCubit]/`WebViewSessionHandle` (PRD
/// §10 boundary).
///
/// RAM-critical detail (§26/§27): on mobile, this widget listens to
/// [MobileWebViewSessionHandle.shouldBeMounted] and actually removes the
/// `InAppWebView` element from the tree when it flips to false — that
/// unmount is what lets the native Android View / WKWebView be
/// garbage-collected after `unloadFromMemory()`. Just hiding it with
/// `Offstage`/`Visibility` would keep it resident in memory.
class WebViewContainer extends StatelessWidget {
  const WebViewContainer({
    super.key,
    required this.account,
    required this.sessionState,
  });

  final Account? account;
  final SessionState sessionState;

  @override
  Widget build(BuildContext context) {
    // Check status BEFORE the null-account check. SessionCubit now sets
    // activeAccountId optimistically as soon as an account is tapped (see
    // switchTo()), so `account` should be non-null whenever status is
    // loading/reconnecting/error — but if it's ever still null (e.g. the
    // account was deleted mid-switch), we still want loading/error to be
    // visible rather than falling back to the empty state, which is what
    // made clicks look like they did nothing.
    switch (sessionState.status) {
      case ActiveSessionStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ActiveSessionStatus.reconnecting:
        return const _ReconnectingState();
      case ActiveSessionStatus.error:
        return _ErrorState(message: sessionState.errorMessage);
      case ActiveSessionStatus.none:
      case ActiveSessionStatus.ready:
        break;
    }

    if (account == null) {
      return const _EmptyState();
    }

    // Only ActiveSessionStatus.none/ready can still reach here — the other
    // cases already returned above.
    return _EngineSurface(account: account!, sessionState: sessionState);
  }
}

class _EngineSurface extends StatelessWidget {
  const _EngineSurface({required this.account, required this.sessionState});

  final Account account;
  final SessionState sessionState;

  @override
  Widget build(BuildContext context) {
    final handle = sessionState.handle;
    if (handle == null) {
      return Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: Text('WhatsApp Web — ${account.name}'),
      );
    }

    if (Platform.isWindows && handle is WindowsWebViewSessionHandle) {
      return win.Webview(handle.controller);
    }

    if (Platform.isLinux && handle is LinuxWebViewSessionHandle) {
      return _LinuxEngineSurface(handle: handle);
    }

    if (handle is MobileWebViewSessionHandle) {
      return _MobileEngineSurface(handle: handle);
    }

    // macOS: not yet PoC'd (§24) — placeholder until its adapter
    // produces a real handle type.
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: Text('WhatsApp Web — ${account.name}\n(engine not wired yet)'),
    );
  }
}

/// Embeds the native `WebKitWebView` that `linux_webview_adapter.dart`
/// creates via `LinuxWebKitPlatformView` — the actual pixels are drawn
/// by GTK in a `GtkFixed` layer stacked on top of the Flutter `FlView`
/// (see `linux/runner/my_application.cc`), NOT by anything Flutter
/// renders itself. This widget's only jobs are:
///  1. Report this widget's on-screen rect to native every frame, so the
///     native view visually tracks wherever Flutter's layout places it
///     (sidebar width changes, window resizes, etc).
///  2. Show/hide the native view on mount/unmount, so switching to a
///     different account (which unmounts this widget) doesn't leave a
///     stale WebKitWebView floating on top of the new content.
///
/// This widget itself paints nothing (fully transparent) — the visible
/// WhatsApp Web content the user sees over this rect comes entirely from
/// the native layer underneath.
class _LinuxEngineSurface extends StatefulWidget {
  const _LinuxEngineSurface({required this.handle});

  final LinuxWebViewSessionHandle handle;

  @override
  State<_LinuxEngineSurface> createState() => _LinuxEngineSurfaceState();
}

class _LinuxEngineSurfaceState extends State<_LinuxEngineSurface> {
  final _boxKey = GlobalKey();
  Timer? _geometryTimer;

  // FIX (typing-lag bug): the previous version called setGeometry() on
  // EVERY timer tick unconditionally, even when nothing on screen had
  // moved. Each call round-tripped through the MethodChannel and forced
  // GTK to run gtk_fixed_move()/gtk_widget_set_size_request() on the
  // WebKitWebView, which forces WebKitGTK to re-run layout on its whole
  // page — including the contenteditable message box. Doing that 10x a
  // second while the user is actively typing is exactly what produced
  // the "lag saat mengetik" symptom, since every keystroke's own reflow
  // was racing against a redundant native relayout the geometry hadn't
  // actually asked for. We now only touch native when the rect actually
  // changed (past a sub-pixel epsilon), which makes this a no-op the
  // vast majority of the time (i.e. whenever the layout is stable —
  // which is precisely when the user is typing).
  Rect? _lastSyncedRect;
  static const double _epsilon = 0.5;

  @override
  void initState() {
    super.initState();
    LinuxWebKitPlatformView.setVisible(
      viewId: widget.handle.accountId,
      visible: true,
    );
    // Polling still catches window resizes / sidebar drags without having
    // to hook every individual Flutter relayout trigger, but the interval
    // can be relaxed (200ms is still visually seamless for a resize drag)
    // now that idle ticks are cheap no-ops instead of forced native
    // relayouts.
    _geometryTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _syncGeometry(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncGeometry());
  }

  void _syncGeometry() {
    if (!mounted) return;
    final renderObject = _boxKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final offset = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    final rect = offset & size;

    final last = _lastSyncedRect;
    if (last != null &&
        (rect.left - last.left).abs() < _epsilon &&
        (rect.top - last.top).abs() < _epsilon &&
        (rect.width - last.width).abs() < _epsilon &&
        (rect.height - last.height).abs() < _epsilon) {
      // Nothing meaningfully moved since the last sync — skip the native
      // call entirely instead of re-issuing an identical geometry update.
      return;
    }
    _lastSyncedRect = rect;

    // NOTE (unverified — no Flutter/GTK build available to test this
    // against): assumes Flutter's logical-pixel coordinate space maps
    // 1:1 onto the GTK widget-relative pixel space `gtk_fixed_move`
    // expects (both should already be scaled consistently by the same
    // GDK/device pixel ratio). If the embedded view appears offset or
    // wrongly sized on your setup, that assumption is the first thing
    // to check — try multiplying/dividing by
    // `MediaQuery.of(context).devicePixelRatio` here.
    LinuxWebKitPlatformView.setGeometry(
      viewId: widget.handle.accountId,
      x: offset.dx,
      y: offset.dy,
      width: size.width,
      height: size.height,
    );
  }

  @override
  void dispose() {
    _geometryTimer?.cancel();
    LinuxWebKitPlatformView.setVisible(
      viewId: widget.handle.accountId,
      visible: false,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // NotificationListener catches size changes (window resize, sidebar
    // drag) the instant layout happens, instead of waiting for the next
    // timer tick — keeps a resize feeling responsive even though the
    // fallback timer above was slowed down.
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncGeometry());
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: SizedBox.expand(key: _boxKey),
      ),
    );
  }
}

/// Watches [MobileWebViewSessionHandle.shouldBeMounted] so that
/// `unloadFromMemory()` results in an actual widget-tree removal, not
/// just an invisible-but-still-resident WebView (see class doc above).
class _MobileEngineSurface extends StatelessWidget {
  const _MobileEngineSurface({required this.handle});

  final MobileWebViewSessionHandle handle;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: handle.shouldBeMounted,
      builder: (context, mounted, _) {
        if (!mounted) {
          // Deliberately returns an empty box rather than keeping the
          // InAppWebView in the tree — this is the unmount that frees
          // native memory once handle.unloadFromMemory() has run.
          return const SizedBox.shrink();
        }
        return InAppWebView(
          initialSettings: handle.settings,
          onWebViewCreated: handle.bindController,
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Tambahkan atau pilih akun WhatsApp untuk memulai'),
    );
  }
}

class _ReconnectingState extends StatelessWidget {
  const _ReconnectingState();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Menyambungkan kembali...'),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text('Gagal memuat sesi.', textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}