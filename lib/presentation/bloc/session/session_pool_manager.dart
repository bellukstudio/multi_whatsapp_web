import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;

import 'package:multi_whatsapp_web/core/constants/app_constants.dart';
import 'package:multi_whatsapp_web/core/utils/memory_profiler.dart';
import 'package:multi_whatsapp_web/domain/entities/account.dart';
import 'package:multi_whatsapp_web/domain/repositories/webview_adapter.dart';

class SessionPoolManager {
  SessionPoolManager({
    required WebViewAdapter webViewAdapter,
    int? maxWarmSessions,
    Duration? idleEvictionTimeout,
    Duration? idleSweepInterval,
    Duration? activeSessionReloadInterval,
  }) : _adapter = webViewAdapter,
       _maxWarmSessions =
           maxWarmSessions ?? AppConstants.maxRecommendedDesktopSessions,
       _idleEvictionTimeout =
           idleEvictionTimeout ?? const Duration(minutes: 10) {
    final interval =
        idleSweepInterval ??
        Duration(
          seconds: (_idleEvictionTimeout.inSeconds / 2).clamp(30, 300).toInt(),
        );
    _idleSweepTimer = Timer.periodic(interval, (_) => _sweepIdleSessions());

    // FIX (memory growing unboundedly the longer an account is actively
    // used — e.g. observed climbing to ~900MB-1.2GB on real usage):
    // `_sweepIdleSessions()` above only ever touches BACKGROUNDED
    // accounts (the ones in `_pausedSince`) — the currently ACTIVE
    // account is deliberately skipped there and is never added to
    // `_pausedSince` in the first place, so nothing in this class ever
    // reclaimed memory it built up (decoded images/video, growing JS
    // heap from chat history) just from being scrolled through and used
    // normally over a long session. A periodic reload of whichever
    // account is currently active resets that WebProcess back to a
    // fresh baseline — an ordinary page reload (WhatsApp Web's own
    // service worker/local storage restores the chat view), not a
    // logout, since cookies/session data live on disk per-account.
    _activeReloadTimer = Timer.periodic(
      activeSessionReloadInterval ?? const Duration(hours: 2),
      (_) => _reloadActiveSession(),
    );
  }

  final WebViewAdapter _adapter;
  final int _maxWarmSessions;
  final Duration _idleEvictionTimeout;
  late final Timer _idleSweepTimer;
  late final Timer _activeReloadTimer;

  final LinkedHashMap<String, WebViewSessionHandle> _warm =
      LinkedHashMap<String, WebViewSessionHandle>();

  final Map<String, DateTime> _pausedSince = {};

  String? _activeAccountId;

  Future<void> _lock = Future<void>.value();

  int get warmCount => _warm.length;

  Future<WebViewSessionHandle> acquire(Account account) {
    final result = _lock.then((_) => _acquireLocked(account));

    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<WebViewSessionHandle> _acquireLocked(Account account) async {
    final previousActiveId = _activeAccountId;

    print(
      '[SessionPoolManager] acquire(${account.id}) — warmCount=${_warm.length} '
      '(cap=$_maxWarmSessions), already warm=${_warm.containsKey(account.id)}, '
      'warm ids=${_warm.keys.toList()}',
    );

    if (_warm.containsKey(account.id)) {
      final handle = _warm.remove(account.id)!;
      _warm[account.id] = handle;
      await handle.resumeRendering();
      _activeAccountId = account.id;
      _pausedSince.remove(account.id);
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

    _warm[account.id] = handle;
    _activeAccountId = account.id;
    _pausedSince.remove(account.id);

    try {
      await handle.navigateToWhatsAppWeb();
    } catch (e) {
      rethrow;
    }

    await _pauseIfStillWarm(previousActiveId);
    return handle;
  }

  Future<void> _pauseIfStillWarm(String? accountId) async {
    if (accountId == null || accountId == _activeAccountId) return;
    final handle = _warm[accountId];
    if (handle != null) {
      await handle.pauseRendering();
      _pausedSince[accountId] = DateTime.now();
    }
  }

  Future<void> _sweepIdleSessions() async {
    final now = DateTime.now();
    final idleIds = _pausedSince.entries
        .where((e) => now.difference(e.value) >= _idleEvictionTimeout)
        .map((e) => e.key)
        .toList(growable: false);

    for (final id in idleIds) {
      if (id == _activeAccountId) {
        _pausedSince.remove(id);
        continue;
      }
      final handle = _warm.remove(id);
      _pausedSince.remove(id);
      if (handle == null) continue;
      await MemoryProfiler.logAround(
        'idle-unload session $id (paused >= ${_idleEvictionTimeout.inMinutes}m)',
        () async {
          await handle.unloadFromMemory();
          await handle.dispose();
        },
      );
    }
  }

  Future<void> _reloadActiveSession() async {
    final activeId = _activeAccountId;
    if (activeId == null) return;
    final handle = _warm[activeId];
    if (handle == null) return;
    await MemoryProfiler.logAround(
      'periodic reload of active session $activeId (reclaim memory)',
      () => handle.reload(),
    );
  }

  Future<void> _evictLeastRecentlyUsed() async {
    if (_warm.isEmpty) return;
    final lruId = _warm.keys.first;

    final handle = _warm.remove(lruId);
    _pausedSince.remove(lruId);
    if (handle != null) {
      await MemoryProfiler.logAround('evict LRU session $lruId', () async {
        await handle.unloadFromMemory();
        await handle.dispose();
      });

      if (Platform.isWindows) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }
  }

  Future<void> evict(String accountId) async {
    final handle = _warm.remove(accountId);
    _pausedSince.remove(accountId);
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
    _pausedSince.clear();
    _activeAccountId = null;
  }

  void dispose() {
    _idleSweepTimer.cancel();
    _activeReloadTimer.cancel();
  }
}