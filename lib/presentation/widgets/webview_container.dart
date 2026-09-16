import 'dart:async';
import 'dart:io' show Platform;

import 'package:desktop_drop/desktop_drop.dart';
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
  bool _dragging = false;
  Timer? _dragExitTimer;
  ModalRoute<void>? _subscribedRoute;

  @override
  void initState() {
    super.initState();
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
    _dragExitTimer?.cancel();
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

    return DropTarget(
      // A Windows platform view can briefly make desktop_drop report a drag
      // exit while the cursor is still over this surface. Do not immediately
      // clear the state: that transient exit made the drag/attachment preview
      // flicker on and off.
      onDragEntered: _handleDragEntered,
      onDragExited: _handleDragExited,
      onDragDone: _handleDrop,
      child: Stack(
        fit: StackFit.expand,
        children: [
          win.Webview(widget.handle.controller),
          if (_dragging)
            IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: 0.25),
                alignment: Alignment.center,
                child: const Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Text('Lepas untuk mengirim file'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleDragEntered(DropEventDetails _) {
    _dragExitTimer?.cancel();
    if (!_dragging && mounted) {
      setState(() => _dragging = true);
    }
  }

  void _handleDragExited(DropEventDetails _) {
    _dragExitTimer?.cancel();
    // Keep the indicator during a transient platform-view boundary crossing.
    // A real exit remains hidden after this short grace period.
    _dragExitTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted && _dragging) {
        setState(() => _dragging = false);
      }
    });
  }

  // Sends the drop through WebView2's native drag-and-drop pipeline. Unlike
  // DOM events or a file-picker automation, WhatsApp receives a trusted
  // CF_HDROP payload at the point where the user released the files.
  Future<void> _handleDrop(DropDoneDetails detail) async {
    if (detail.files.isEmpty) return;
    _dragExitTimer?.cancel();
    if (_dragging && mounted) {
      setState(() => _dragging = false);
    }
    if (!mounted) return;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      debugPrint('[file-drop] webview bounds are unavailable.');
      return;
    }

    final point = renderObject.globalToLocal(detail.globalPosition);
    final accepted = await widget.handle.controller.dropFile(
      detail.files.map((file) => file.path).toList(growable: false),
      point.dx,
      point.dy,
    );
    debugPrint(
      '[file-drop] native WebView2 drop: $accepted '
      'at ${point.dx.toStringAsFixed(1)},${point.dy.toStringAsFixed(1)}',
    );
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
