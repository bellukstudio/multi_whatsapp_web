import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:multi_whatsapp_web/data/datasources/webview/mobile/slot_embed_webview_session_handle.dart';
import 'package:multi_whatsapp_web/domain/repositories/webview_adapter.dart';

import 'package:webview_windows/webview_windows.dart' as win;

import '../../app.dart' show desktopWebViewRouteObserver;
import '../../core/utils/app_restarter.dart';
import '../../data/datasources/webview/desktop/linux_webview_adapter.dart';
import '../../data/datasources/webview/desktop/linux_webkit_platform_view.dart';
import '../../data/datasources/webview/desktop/windows_webview_adapter.dart';
import '../../domain/entities/account.dart';
import '../bloc/session/session_cubit.dart';

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
    switch (sessionState.status) {
      case ActiveSessionStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ActiveSessionStatus.reconnecting:
        return const _ReconnectingState();
      case ActiveSessionStatus.error:
        debugPrint(sessionState.errorMessage);

        return _ErrorState(
          message: sessionState.errorMessage,
          needsAppRestart: sessionState.errorNeedsAppRestart,
        );
      case ActiveSessionStatus.none:
      case ActiveSessionStatus.ready:
        break;
    }

    if (account == null) {
      return const _EmptyState();
    }

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
      return _WindowsEngineSurface(handle: handle);
    }

    if (Platform.isLinux && handle is LinuxWebViewSessionHandle) {
      return _LinuxEngineSurface(handle: handle);
    }
    if (handle is SlotEmbedWebViewSessionHandle) {
      return _MobileEngineSurface(handle: handle);
    }
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: Text('WhatsApp Web — ${account.name}\n(engine not wired yet)'),
    );
  }
}

class _WindowsEngineSurface extends StatefulWidget {
  const _WindowsEngineSurface({required this.handle});

  final WindowsWebViewSessionHandle handle;

  @override
  State<_WindowsEngineSurface> createState() => _WindowsEngineSurfaceState();
}

class _WindowsEngineSurfaceState extends State<_WindowsEngineSurface>
    with RouteAware {
  bool _mounted = true;
  ModalRoute<void>? _subscribedRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _subscribedRoute) {
      if (_subscribedRoute != null) {
        desktopWebViewRouteObserver.unsubscribe(this);
      }
      _subscribedRoute = route;
      if (route != null) {
        desktopWebViewRouteObserver.subscribe(this, route);
      }
    }
  }

  @override
  void didPushNext() {
    if (mounted) setState(() => _mounted = false);
  }

  @override
  void didPopNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _mounted = true);
    });
  }

  @override
  void dispose() {
    if (_subscribedRoute != null) {
      desktopWebViewRouteObserver.unsubscribe(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_mounted) {
      return const SizedBox.shrink();
    }
    return win.Webview(widget.handle.controller);
  }
}

class _LinuxEngineSurface extends StatefulWidget {
  const _LinuxEngineSurface({required this.handle});

  final LinuxWebViewSessionHandle handle;

  @override
  State<_LinuxEngineSurface> createState() => _LinuxEngineSurfaceState();
}

class _LinuxEngineSurfaceState extends State<_LinuxEngineSurface>
    with RouteAware {
  final _boxKey = GlobalKey();
  Timer? _geometryTimer;

  ModalRoute<void>? _subscribedRoute;

  Rect? _lastSyncedRect;
  static const double _epsilon = 0.5;

  @override
  void initState() {
    super.initState();
    LinuxWebKitPlatformView.setVisible(
      viewId: widget.handle.accountId,
      visible: true,
    );

    _geometryTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _syncGeometry(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncGeometry());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final route = ModalRoute.of(context);
    if (route != _subscribedRoute) {
      if (_subscribedRoute != null) {
        desktopWebViewRouteObserver.unsubscribe(this);
      }
      _subscribedRoute = route;
      if (route != null) {
        desktopWebViewRouteObserver.subscribe(this, route);
      }
    }
  }

  @override
  void didUpdateWidget(covariant _LinuxEngineSurface oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.handle.accountId != widget.handle.accountId) {
      LinuxWebKitPlatformView.setVisible(
        viewId: oldWidget.handle.accountId,
        visible: false,
      );
      _lastSyncedRect = null;
      if (_subscribedRoute?.isCurrent ?? true) {
        LinuxWebKitPlatformView.setVisible(
          viewId: widget.handle.accountId,
          visible: true,
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncGeometry());
    }
  }

  @override
  void didPushNext() {
    LinuxWebKitPlatformView.setVisible(
      viewId: widget.handle.accountId,
      visible: false,
    );
  }

  @override
  void didPopNext() {
    LinuxWebKitPlatformView.setVisible(
      viewId: widget.handle.accountId,
      visible: true,
    );
    _lastSyncedRect = null;
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
      return;
    }
    _lastSyncedRect = rect;

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
    if (_subscribedRoute != null) {
      desktopWebViewRouteObserver.unsubscribe(this);
    }
    LinuxWebKitPlatformView.setVisible(
      viewId: widget.handle.accountId,
      visible: false,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncGeometry());
        return true;
      },
      child: SizeChangedLayoutNotifier(child: SizedBox.expand(key: _boxKey)),
    );
  }
}

class _MobileEngineSurface extends StatelessWidget {
  const _MobileEngineSurface({required this.handle});

  final WebViewSessionHandle handle;

  @override
  Widget build(BuildContext context) {
    if (handle is SlotEmbedWebViewSessionHandle) {
      // FIX (masih terasa "reload" tiap pindah akun di Android): tanpa
      // `key` di sini, Flutter menganggap ini widget yang SAMA persis
      // tiap kali handle berganti (StatelessWidget + tipe sama + key
      // null == null), jadi `SlotEmbedWebView`/`AndroidView` di
      // dalamnya TIDAK dibuat ulang — `creationParams` (slot +
      // accountId) yang baru tidak pernah benar-benar dikirim ke sisi
      // native, karena AndroidView hanya membaca creationParams sekali
      // saat pertama kali dibuat. Akibatnya, setelah pindah akun lebih
      // dari sekali, layar bisa nyangkut menampilkan akun sebelumnya,
      // yang secara UX kerasa seperti "reload"/glitch tiap ganti akun.
      //
      // Dengan `ValueKey(accountId)`, tiap akun punya identitas Element
      // sendiri: pindah akun benar-benar membuang widget/AndroidView
      // lama (memicu `SlotEmbedView.dispose()` -> HANYA unbind, sesuai
      // fix di Kotlin) dan memasang yang baru dengan creationParams
      // yang benar — WebView & sesi di proses native TETAP hidup
      // (tidak reload beneran), cuma di-attach ulang ke slot yang
      // tepat.
      return SlotEmbedWebView(
        key: ValueKey('slot_embed_${handle.accountId}'),
        handle: handle as SlotEmbedWebViewSessionHandle,
      );
    }
    return const Center(
      child: Text('WebView native iOS belum tersedia — menyusul.'),
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
  const _ErrorState({this.message, this.needsAppRestart = false});

  final String? message;

  final bool needsAppRestart;

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
                '$message',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (needsAppRestart) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => AppRestarter.restart(),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Restart Aplikasi'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
