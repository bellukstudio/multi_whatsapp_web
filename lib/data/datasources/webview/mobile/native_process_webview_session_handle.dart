import 'dart:async';

import 'package:flutter/services.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../domain/repositories/webview_adapter.dart';

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
            'sesi app ini. Restart app untuk membebaskan slot (lihat class '
            'doc SlotAllocator untuk kenapa ini tidak bisa dibebaskan tanpa '
            'restart).',
      );
    }
    _slotToAccount[freeIndex] = accountId;
    _accountToSlot[accountId] = freeIndex;
    return freeIndex;
  }

  int get boundCount => _accountToSlot.length;
}

class NativeProcessWebViewSessionHandle implements WebViewSessionHandle {
  NativeProcessWebViewSessionHandle({
    required this.accountId,
    required this.accountName,
  });

  static const _channel = MethodChannel('multi_whatsapp_web/webview_slots');

  static int? themeColorArgb;

  @override
  final String accountId;

  final String accountName;

  final _statusController =
  StreamController<AccountConnectionStatus>.broadcast();

  @override
  Stream<AccountConnectionStatus> get statusStream => _statusController.stream;

  @override
  Future<void> navigateToWhatsAppWeb() async {
    _statusController.add(AccountConnectionStatus.connecting);
    final slot = SlotAllocator.instance.slotFor(accountId);
    await _channel.invokeMethod('openSlot', {
      'slot': slot,
      'accountId': accountId,
      'accountName': accountName,
      'initialUrl': AppConstants.whatsappWebUrl,
      'themeColor': themeColorArgb,
    });
    _statusController.add(AccountConnectionStatus.connected);
  }

  @override
  Future<void> reload() async {
  }

  @override
  Future<void> pauseRendering() async {}

  @override
  Future<void> resumeRendering() async {}

  @override
  Future<void> unloadFromMemory() async {
  }

  @override
  Future<int?> approximateMemoryBytes() async => null;

  @override
  Future<void> clearSessionData() async {
    await _channel.invokeMethod('clearSlotData', {
      'slot': SlotAllocator.instance.slotFor(accountId),
    });
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
  }
}