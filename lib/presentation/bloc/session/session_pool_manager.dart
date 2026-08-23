import 'dart:collection';

import 'package:multi_whatsapp_web/core/constants/app_constants.dart';
import 'package:multi_whatsapp_web/core/utils/memory_profiler.dart';
import 'package:multi_whatsapp_web/domain/entities/account.dart';
import 'package:multi_whatsapp_web/domain/repositories/webview_adapter.dart';

/// Desktop-only session pool with a soft LRU cap (PRD §26: "10 akun:
/// tidak crash, resource dimonitor" — read as "don't let 10 open accounts
/// mean 10 fully-rendering WebViews forever").
///
/// Policy:
///   - Up to [maxWarmSessions] accounts may have a live WebView at once.
///   - The currently *visible* account is always kept fully active.
///   - Other warm accounts are [WebViewAdapter.pauseRendering]'d (cheap —
///     keeps cookies/DOM state, throttles JS) rather than unloaded.
///   - When a session beyond the cap is requested, the Least Recently
///     Used warm session is evicted via [WebViewAdapter.unloadFromMemory]
///     + [WebViewSessionHandle.dispose] before the new one is created.
///
/// Mobile does NOT use this pool — [SessionCubit] talks to the adapter
/// directly there, since §27 mandates at most one warm session, period.
class SessionPoolManager {
  SessionPoolManager({
    required WebViewAdapter webViewAdapter,
    int? maxWarmSessions,
  }) : _adapter = webViewAdapter,
       _maxWarmSessions =
           maxWarmSessions ?? AppConstants.maxRecommendedDesktopSessions;

  final WebViewAdapter _adapter;
  final int _maxWarmSessions;

  /// LinkedHashMap preserves insertion order; we re-insert on access to
  /// get cheap LRU-order tracking (oldest = least recently used = first).
  final LinkedHashMap<String, WebViewSessionHandle> _warm =
      LinkedHashMap<String, WebViewSessionHandle>();

  String? _activeAccountId;

  int get warmCount => _warm.length;

  /// Makes [account] the active, fully-rendering session. Evicts the LRU
  /// warm session first if the pool is at capacity and [account] isn't
  /// already warm.
  Future<WebViewSessionHandle> acquire(Account account) async {
    final previousActiveId = _activeAccountId;

    if (_warm.containsKey(account.id)) {
      // Already warm — just promote to MRU and resume full rendering.
      final handle = _warm.remove(account.id)!;
      _warm[account.id] = handle; // re-insert = move to MRU end
      await handle.resumeRendering();
      _activeAccountId = account.id;
      await _pauseIfStillWarm(previousActiveId);
      return handle;
    }

    if (_warm.length >= _maxWarmSessions) {
      await _evictLeastRecentlyUsed();
    }

    final handle = await MemoryProfiler.logAround(
      'create session ${account.id}',
      () => _adapter.createOrResumeSession(
        accountId: account.id,
        sessionPath: account.sessionPath,
      ),
    );
    await handle.navigateToWhatsAppWeb();
    _warm[account.id] = handle;
    _activeAccountId = account.id;

    await _pauseIfStillWarm(previousActiveId);
    return handle;
  }

  Future<void> _pauseIfStillWarm(String? accountId) async {
    if (accountId == null || accountId == _activeAccountId) return;
    final handle = _warm[accountId];
    if (handle != null) {
      await handle.pauseRendering();
    }
  }

  Future<void> _evictLeastRecentlyUsed() async {
    if (_warm.isEmpty) return;
    final lruId = _warm.keys.first; // first-inserted = least recently used
    if (lruId == _activeAccountId) {
      // Shouldn't normally happen (active is always MRU), but guard
      // against evicting the visible session.
      return;
    }
    final handle = _warm.remove(lruId);
    if (handle != null) {
      await MemoryProfiler.logAround('evict LRU session $lruId', () async {
        await handle.unloadFromMemory();
        await handle.dispose();
      });
    }
  }

  /// Optional explicit eviction, e.g. when an account is deleted (§12) —
  /// don't wait for LRU pressure to release its memory.
  Future<void> evict(String accountId) async {
    final handle = _warm.remove(accountId);
    if (handle == null) return;
    await handle.unloadFromMemory();
    await handle.dispose();
    if (_activeAccountId == accountId) _activeAccountId = null;
  }

  Future<void> disposeAll() async {
    for (final handle in _warm.values) {
      await handle.unloadFromMemory();
      await handle.dispose();
    }
    _warm.clear();
    _activeAccountId = null;
  }
}
