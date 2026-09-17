import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:multi_whatsapp_web/data/datasources/webview/mobile/slot_embed_webview_session_handle.dart';
import 'package:multi_whatsapp_web/domain/repositories/webview_adapter.dart';

import 'package:webview_windows/webview_windows.dart' as win;

import '../../app.dart' show desktopWebViewRouteObserver;
import '../../core/utils/app_restarter.dart';
import '../../core/utils/file_drop_injection.dart';
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

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
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
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Text('Lepas untuk mengirim file'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleDrop(DropDoneDetails detail) async {
    if (detail.files.isEmpty) return;
    setState(() => _dragging = false);

    final payloads = <DroppedFilePayload>[];
    for (final file in detail.files) {
      final bytes = await file.readAsBytes();
      payloads.add(
        DroppedFilePayload(
          name: file.name,
          mimeType: file.mimeType ?? guessMimeType(file.name),
          bytesBase64: base64Encode(bytes),
        ),
      );
    }
    if (!mounted) return;

    final allImages = payloads.every(
      (p) => p.mimeType.startsWith('image/') || p.mimeType.startsWith('video/'),
    );

    // PENTING: dulu blok attach-menu ini di-skip untuk kasus "allImages",
    // sehingga targetInputIndex tetap null dan finish-script jatuh ke
    // strategi "broadcast-all" (menyetel file ke SEMUA input[type=file] di
    // halaman) — inilah yang membuat gambar yang di-drop malah terkirim
    // sebagai stiker (ada input tersembunyi milik sticker maker yang ikut
    // menerima file). Sekarang gambar/video JUGA selalu diarahkan lewat
    // attach menu ("Photos & videos"), sama seperti dokumen, supaya kita
    // selalu tahu & menandai input yang tepat.
    final isDocumentFlow = !allImages;

    int? targetInputIndex;

    final openResult = await widget.handle.controller.executeScript(
      buildOpenAttachMenuScript(),
    );
    debugPrint('[file-drop] open-attach-menu: $openResult');
    await Future.delayed(const Duration(milliseconds: 200));

    final clickResult = await widget.handle.controller.executeScript(
      isDocumentFlow
          ? buildClickDocumentMenuItemScript()
          : buildClickPhotosMenuItemScript(),
    );
    debugPrint('[file-drop] click-menu-item: $clickResult');

    final clickOk = (clickResult is Map && clickResult['ok'] == true);
    if (!clickOk) {
      debugPrint(
        '[file-drop] ABORT: gagal klik item menu '
        '(${isDocumentFlow ? 'Document' : 'Photos & videos'})',
      );
      return;
    }
    await Future.delayed(const Duration(milliseconds: 300));

    int? found;
    for (var attempt = 0; attempt < 10; attempt++) {
      final findResult = await widget.handle.controller.executeScript(
        isDocumentFlow
            ? buildFindDocumentInputScript()
            : buildFindMediaInputScript(),
      );
      debugPrint('[file-drop] find-input attempt $attempt: $findResult');
      if (findResult is Map) {
        final idx = findResult['docIndex'];
        if (idx is int && idx != -1) {
          found = idx;
          break;
        }
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }

    if (found == null) {
      debugPrint(
        '[file-drop] ABORT: input target tidak ditemukan setelah klik menu '
        '(${isDocumentFlow ? 'Document' : 'Photos & videos'})',
      );
      return;
    }
    targetInputIndex = found;

    final initResult = await widget.handle.controller.executeScript(
      buildChunkedTransferInitScript(payloads),
    );
    debugPrint('[file-drop] chunk-init: $initResult');

    for (var i = 0; i < payloads.length; i++) {
      final b64 = payloads[i].bytesBase64;
      var offset = 0;
      var chunkCount = 0;
      while (offset < b64.length) {
        final end = (offset + fileChunkBase64Size < b64.length)
            ? offset + fileChunkBase64Size
            : b64.length;
        await widget.handle.controller.executeScript(
          buildChunkedTransferAppendScript(i, b64.substring(offset, end)),
        );
        offset = end;
        chunkCount++;
      }
      debugPrint(
        '[file-drop] chunk-append: file $i (${payloads[i].name}) sent in $chunkCount chunk(s)',
      );
    }

    final inputResult = await widget.handle.controller.executeScript(
      buildChunkedTransferFinishScript(targetInputIndex: targetInputIndex),
    );
    debugPrint('[file-drop] input-populate: $inputResult');
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

  // --- Drag & drop (lihat LinuxWebKitPlatformView / OnDragMotion di
  // webkit_multi_view_plugin.cc untuk kenapa ini datang dari native, bukan
  // dari DropTarget Flutter biasa seperti di Windows). ---
  bool _dragging = false;
  StreamSubscription<String>? _dragEnteredSub;
  StreamSubscription<String>? _dragExitedSub;
  StreamSubscription<LinuxFileDropEvent>? _dropSub;

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

    _dragEnteredSub = LinuxWebKitPlatformView.onDragEntered.listen((viewId) {
      if (viewId == widget.handle.accountId && mounted && !_dragging) {
        setState(() => _dragging = true);
      }
    });
    _dragExitedSub = LinuxWebKitPlatformView.onDragExited.listen((viewId) {
      if (viewId == widget.handle.accountId && mounted && _dragging) {
        setState(() => _dragging = false);
      }
    });
    _dropSub = LinuxWebKitPlatformView.onFilesDropped.listen((event) {
      if (event.viewId == widget.handle.accountId) {
        if (mounted) setState(() => _dragging = false);
        unawaited(_handleDrop(event.paths));
      }
    });
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
    _dragEnteredSub?.cancel();
    _dragExitedSub?.cancel();
    _dropSub?.cancel();
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
    return Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _syncGeometry());
            return true;
          },
          child: SizeChangedLayoutNotifier(child: SizedBox.expand(key: _boxKey)),
        ),
        // IgnorePointer: WebKitWebView native ada di layer TERPISAH di atas
        // Flutter (lihat komentar di webkit_multi_view_plugin.cc), jadi
        // overlay ini murni visual — tidak pernah benar-benar menangkap
        // event mouse/drag, dan memang tidak perlu.
        if (_dragging)
          IgnorePointer(
            child: Container(
              color: Colors.black.withValues(alpha: 0.25),
              alignment: Alignment.center,
              child: const Card(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Text('Lepas untuk mengirim file'),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _handleDrop(List<String> paths) async {
    if (paths.isEmpty) return;
    final viewId = widget.handle.accountId;

    final payloads = <DroppedFilePayload>[];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      final name = p.basename(path);
      payloads.add(
        DroppedFilePayload(
          name: name,
          mimeType: guessMimeType(name),
          bytesBase64: base64Encode(bytes),
        ),
      );
    }
    if (payloads.isEmpty || !mounted) return;

    final allImages = payloads.every(
      (payload) =>
          payload.mimeType.startsWith('image/') ||
          payload.mimeType.startsWith('video/'),
    );

    // Lihat komentar senada di _WindowsEngineSurfaceState._handleDrop:
    // gambar/video JUGA harus diarahkan lewat attach menu ("Photos &
    // videos"), bukan di-skip, supaya targetInputIndex selalu terisi dan
    // finish-script tidak jatuh ke strategi "broadcast-all" (yang bisa
    // mengenai input tersembunyi milik sticker maker WhatsApp Web).
    final isDocumentFlow = !allImages;

    int? targetInputIndex;

    final openResult = await LinuxWebKitPlatformView.runJavaScript(
      viewId: viewId,
      script: buildOpenAttachMenuScript(),
    );
    debugPrint('[file-drop][linux] open-attach-menu: $openResult');
    await Future.delayed(const Duration(milliseconds: 200));

    final clickResult = await LinuxWebKitPlatformView.runJavaScript(
      viewId: viewId,
      script: isDocumentFlow
          ? buildClickDocumentMenuItemScript()
          : buildClickPhotosMenuItemScript(),
    );
    debugPrint('[file-drop][linux] click-menu-item: $clickResult');

    final clickOk = (clickResult is Map && clickResult['ok'] == true);
    if (!clickOk) {
      debugPrint(
        '[file-drop][linux] ABORT: gagal klik item menu '
        '(${isDocumentFlow ? 'Document' : 'Photos & videos'})',
      );
      return;
    }
    await Future.delayed(const Duration(milliseconds: 300));

    int? found;
    for (var attempt = 0; attempt < 10; attempt++) {
      final findResult = await LinuxWebKitPlatformView.runJavaScript(
        viewId: viewId,
        script: isDocumentFlow
            ? buildFindDocumentInputScript()
            : buildFindMediaInputScript(),
      );
      debugPrint('[file-drop][linux] find-input attempt $attempt: $findResult');
      if (findResult is Map) {
        final idx = findResult['docIndex'];
        if (idx is int && idx != -1) {
          found = idx;
          break;
        }
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }

    if (found == null) {
      debugPrint(
        '[file-drop][linux] ABORT: input target tidak ditemukan setelah klik menu '
        '(${isDocumentFlow ? 'Document' : 'Photos & videos'})',
      );
      return;
    }
    targetInputIndex = found;

    final initResult = await LinuxWebKitPlatformView.runJavaScript(
      viewId: viewId,
      script: buildChunkedTransferInitScript(payloads),
    );
    debugPrint('[file-drop][linux] chunk-init: $initResult');

    for (var i = 0; i < payloads.length; i++) {
      final b64 = payloads[i].bytesBase64;
      var offset = 0;
      var chunkCount = 0;
      while (offset < b64.length) {
        final end = (offset + fileChunkBase64Size < b64.length)
            ? offset + fileChunkBase64Size
            : b64.length;
        await LinuxWebKitPlatformView.runJavaScript(
          viewId: viewId,
          script: buildChunkedTransferAppendScript(i, b64.substring(offset, end)),
        );
        offset = end;
        chunkCount++;
      }
      debugPrint(
        '[file-drop][linux] chunk-append: file $i (${payloads[i].name}) sent in $chunkCount chunk(s)',
      );
    }

    final inputResult = await LinuxWebKitPlatformView.runJavaScript(
      viewId: viewId,
      script: buildChunkedTransferFinishScript(targetInputIndex: targetInputIndex),
    );
    debugPrint('[file-drop][linux] input-populate: $inputResult');
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