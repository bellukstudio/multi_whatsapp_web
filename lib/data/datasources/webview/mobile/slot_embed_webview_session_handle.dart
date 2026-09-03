import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/repositories/webview_adapter.dart';

/// Same slot-allocation rules as before (see class doc) — still needed
/// here because `WebView.setDataDirectorySuffix()` is still called
/// exactly once per process (now inside `WebViewSlotServiceN`, not an
/// Activity), so the same "fixed number of slots, bound for the life of
/// the app run" constraint applies.
class SlotAllocator {
  SlotAllocator._();
  static final SlotAllocator instance = SlotAllocator._();

  static const int slotCount = 6;

  final Map<String, int> _accountToSlot = {};
  final List<String?> _slotToAccount = List.filled(slotCount, null);

  int slotFor(String accountId) {
    final existing = _accountToSlot[accountId];
    if (existing != null) return existing;

    final freeIndex = _slotToAccount.indexOf(null);
    if (freeIndex == -1) {
      throw StateError(
        'Semua $slotCount slot proses WebView sudah dipakai akun lain di '
            'sesi app ini. Restart app untuk membebaskan slot.',
      );
    }
    _slotToAccount[freeIndex] = accountId;
    _accountToSlot[accountId] = freeIndex;
    return freeIndex;
  }
}

/// Embeds `SlotEmbedView` (a same-process `SurfaceView` in the Flutter
/// tree that projects a REMOTE process's WebView content into itself
/// via `SurfaceControlViewHost`) — see `SlotEmbedView.kt` +
/// `WebViewSlotService.kt` for the native side, and their ⚠️ notes on
/// what's least certain without live testing.
///
/// Unlike the previous Activity-based approach, this handle has almost
/// nothing to do itself — the actual attach/render handshake happens
/// entirely natively once the `AndroidView` below is created. This
/// handle mainly exists to satisfy [WebViewSessionHandle] and hold the
/// slot index so the widget knows which native service to bind to.
class SlotEmbedWebViewSessionHandle implements WebViewSessionHandle {
  SlotEmbedWebViewSessionHandle({
    required this.accountId,
    required this.accountName,
  });

  @override
  final String accountId;

  final String accountName;

  late final int slot = SlotAllocator.instance.slotFor(accountId);

  final _statusController =
  StreamController<AccountConnectionStatus>.broadcast();

  @override
  Stream<AccountConnectionStatus> get statusStream => _statusController.stream;

  @override
  Future<void> navigateToWhatsAppWeb() async {
    // No-op here — the AndroidView itself triggers the native
    // attach/load sequence on creation (see SlotEmbedView.kt). This just
    // reports a status for UI consistency with other platforms.
    _statusController.add(AccountConnectionStatus.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _statusController.add(AccountConnectionStatus.connected);
  }

  @override
  Future<void> reload() async {}

  @override
  Future<void> pauseRendering() async {}

  @override
  Future<void> resumeRendering() async {}

  @override
  Future<void> unloadFromMemory() async {
    // The AndroidView's own dispose() (triggered when it's removed from
    // the widget tree) sends MSG_RELEASE to the remote service — see
    // SlotEmbedView.kt's dispose().
  }

  @override
  Future<int?> approximateMemoryBytes() async => null;

  @override
  Future<void> clearSessionData() async {
    // TODO: not wired yet in this cross-process version — would need a
    // new message type to WebViewSlotService (e.g. MSG_CLEAR_DATA)
    // calling CookieManager.getInstance().removeAllCookies() /
    // webView.clearCache() in that process. Left out of this first pass
    // to keep scope manageable; ask if you need this next.
  }

  @override
  Future<void> dispose() async {
    await unloadFromMemory();
    await _statusController.close();
  }
}

/// The actual embedded native content — build this wherever the app
/// currently shows the mobile WebView surface (see
/// `webview_container.dart`'s `_MobileEngineSurface`).
///
/// Shows a loading overlay on top of the `AndroidView` until the native
/// side reports the cross-process `SurfaceControlViewHost` content has
/// actually attached — without this, `SurfaceView` shows solid black
/// (its default, un-drawn-to buffer) for however long the remote
/// process's WebView + attach handshake takes, which looks like a
/// broken/blank screen rather than a loading state.
class SlotEmbedWebView extends StatefulWidget {
  const SlotEmbedWebView({super.key, required this.handle});

  final SlotEmbedWebViewSessionHandle handle;

  @override
  State<SlotEmbedWebView> createState() => _SlotEmbedWebViewState();
}

class _SlotEmbedWebViewState extends State<SlotEmbedWebView> {
  bool _attached = false;
  String? _attachError;
  MethodChannel? _channel;

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('multi_whatsapp_web/slot_embed_$viewId');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'attached':
        // FIX (brief black flash even after waiting for
        // onPageCommitVisible natively): attaching ANY SurfaceView
        // content can still show a single black compositor frame due
        // to Android's own buffer-swap timing — not something
        // controllable from the Kotlin side alone. Holding the
        // overlay up for a short buffer AFTER the "attached" signal,
        // then cross-fading it out (see AnimatedSwitcher below)
        // instead of an abrupt switch, hides that residual flash
        // behind the overlay/fade rather than eliminating the native
        // timing quirk itself.
          await Future<void>.delayed(const Duration(milliseconds: 220));
          if (mounted) setState(() => _attached = true);
          break;
        case 'attachFailed':
          if (mounted) {
            setState(() => _attachError = call.arguments as String?);
          }
          break;
      }
      return null;
    });
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AndroidView(
          viewType: 'multi_whatsapp_web/slot_embed',
          creationParams: {
            'slot': widget.handle.slot,
            'accountId': widget.handle.accountId,
            'initialUrl': AppConstants.whatsappWebUrl,
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _attachError != null
              ? ColoredBox(
            key: const ValueKey('error'),
            color: Colors.white,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Gagal menampilkan WebView:\n$_attachError',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
              : (_attached
              ? const SizedBox.shrink(key: ValueKey('done'))
              : const ColoredBox(
            key: ValueKey('loading'),
            color: Colors.white,
            child: Center(child: CircularProgressIndicator()),
          )),
        ),
      ],
    );
  }
}