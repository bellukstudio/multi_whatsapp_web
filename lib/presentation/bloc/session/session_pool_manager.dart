import 'dart:async';
import 'dart:collection';

import 'package:multi_whatsapp_web/core/constants/app_constants.dart';
import 'package:multi_whatsapp_web/core/utils/memory_governor.dart';
import 'package:multi_whatsapp_web/core/utils/memory_profiler.dart';
import 'package:multi_whatsapp_web/domain/entities/account.dart';
import 'package:multi_whatsapp_web/domain/repositories/webview_adapter.dart';

/// Keeps a small set of accounts "warm".
///
/// MEMORY WATCHDOG — what it does and, more importantly, what it does NOT do
/// -----------------------------------------------------------------------
/// The kill message
///
///   `Unable to shrink memory footprint of process (628 MB) below the kill
///    thresold (600 MB). Killed`
///
/// comes from WebKit's own MemoryPressureHandler running inside a single
/// WebKitWebProcess (WTF/wtf/MemoryPressureHandler.cpp). WebKit notices that
/// one process is over ITS OWN limit, calls releaseMemory(Critical::Yes),
/// and kills the process when the footprint still doesn't come down. The
/// Flutter app is not the thing being killed — the account's page is, which
/// is why it comes back blank and reloads in a loop.
///
/// That has two consequences this class is built around, both learned the
/// hard way from a previous version that made things worse:
///
/// 1. The threshold is PER WEB PROCESS. An earlier version compared a
///    summed process-tree figure (1.4 GB over 5 processes) against the
///    600 MB per-process number, so it was over budget permanently, and
///    "relieve pressure" ran on every single poll. That was the reload loop.
///
/// 2. Dart cannot save a web process that is already over the line. WebKit
///    has already tried a synchronous critical release by the time the
///    message is printed; `reload()` moved the figure by 0.1 MB in the logs.
///    Raising the limit and letting WebKit reclaim earlier is a WebKitGTK
///    configuration job — see `linux/runner/webkit_multi_view_plugin.cc`.
///
/// So the watchdog now does only what Dart genuinely can do: free whole
/// background accounts (each its own web process) when the MACHINE is short
/// of memory, at most once every [AppConstants.pressureCooldown]. It never
/// touches the active session, and it is disabled entirely off Linux —
/// WebView2 on Windows has no such kill, and the pool there behaves exactly
/// as it did before any of this.
class SessionPoolManager {
  SessionPoolManager({
    required WebViewAdapter webViewAdapter,
    int? maxWarmSessions,
    Duration? idleEvictionTimeout,
    Duration? idleSweepInterval,
    Duration? activeSessionReloadInterval,
    Duration? memoryPollInterval,
    MemoryGovernor? memoryGovernor,
    bool? enableMemoryWatchdog,
  }) : _adapter = webViewAdapter,
       _maxWarmSessions =
           maxWarmSessions ?? AppConstants.maxRecommendedDesktopSessions,
       _governor = memoryGovernor ?? MemoryGovernor(),
       _watchdogEnabled =
           enableMemoryWatchdog ?? AppConstants.memoryWatchdogEnabled,
       _idleEvictionTimeout =
           // "suspend" only releases the JS heap; the account's WebProcess +
           // NetworkProcess (~150-250MB) stay alive for as long as it is
           // warm. Only idle eviction below (unloadFromMemory -> destroy)
           // actually hands that RAM back.
           idleEvictionTimeout ?? const Duration(minutes: 3) {
    final interval =
        idleSweepInterval ??
        Duration(
          seconds: (_idleEvictionTimeout.inSeconds / 2).clamp(30, 300).toInt(),
        );
    _idleSweepTimer = Timer.periodic(interval, (_) => _sweepIdleSessions());

    // Fallback safety net for the active account, whose memory grows purely
    // from being used (decoded images/video, growing JS heap from chat
    // history). Unchanged from the original, on every platform.
    _activeReloadTimer = Timer.periodic(
      activeSessionReloadInterval ?? const Duration(minutes: 20),
      (_) => _reloadActiveSession(),
    );

    if (_watchdogEnabled) {
      _memoryTimer = Timer.periodic(
        memoryPollInterval ?? AppConstants.memoryPollInterval,
        (_) => _onMemoryTick(),
      );
    }
  }

  final WebViewAdapter _adapter;
  final int _maxWarmSessions;
  final Duration _idleEvictionTimeout;
  final MemoryGovernor _governor;
  final bool _watchdogEnabled;

  late final Timer _idleSweepTimer;
  late final Timer _activeReloadTimer;
  Timer? _memoryTimer;

  final LinkedHashMap<String, WebViewSessionHandle> _warm =
      LinkedHashMap<String, WebViewSessionHandle>();

  final Map<String, DateTime> _pausedSince = {};

  String? _activeAccountId;

  bool _disposed = false;
  bool _relievingPressure = false;
  DateTime? _lastPressureAction;

  Future<void> _lock = Future<void>.value();

  int get warmCount => _warm.length;

  bool isWarm(String accountId) => _warm.containsKey(accountId);

  /// Last reading taken by the watchdog — for the §26 "resource dimonitor"
  /// UI, so it can show per-process figures including the WebKit children
  /// rather than the misleading main-process-only number.
  MemorySnapshot? get lastMemorySnapshot => _lastSnapshot;
  MemorySnapshot? _lastSnapshot;

  Future<T> _runLocked<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<WebViewSessionHandle> acquire(
    Account account, {
    bool keepPaused = false,
  }) {
    return _runLocked(() => _acquireLocked(account, keepPaused));
  }

  Future<WebViewSessionHandle> _acquireLocked(
    Account account,
    bool keepPaused,
  ) async {
    final previousActiveId = _activeAccountId;

    if (_warm.containsKey(account.id)) {
      final handle = _warm.remove(account.id)!;
      _warm[account.id] = handle;
      // Lock safety: on Linux the WebKitWebView is a separate GTK overlay on
      // top of Flutter, so resuming it shows the content regardless of which
      // Flutter widget (e.g. AccountLockedScreen) is drawn behind it. If the
      // caller says this account must stay locked, never resume here — the
      // unlock flow calls resumeRendering() itself.
      if (!keepPaused) {
        await handle.resumeRendering();
      }
      _activeAccountId = account.id;
      _pausedSince.remove(account.id);
      await _pauseIfStillWarm(previousActiveId);
      return handle;
    }

    while (_warm.length >= _maxWarmSessions) {
      final evicted = await _evictLeastRecentlyUsed();
      if (!evicted) break;
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
      // FIX (leak): the failed handle used to stay in `_warm` forever — a
      // live web process nobody could reach, counted against the cap and
      // never evicted because it was also `_activeAccountId`.
      _warm.remove(account.id);
      if (_activeAccountId == account.id) _activeAccountId = null;
      try {
        await handle.unloadFromMemory();
        await handle.dispose();
      } catch (_) {}
      rethrow;
    }

    if (keepPaused) {
      await handle.pauseRendering();
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

  // -------------------------------------------------------------------
  // Memory watchdog (Linux only)
  // -------------------------------------------------------------------

  Future<void> _onMemoryTick() async {
    if (_disposed || _relievingPressure) return;

    final snapshot = await _governor.snapshot();
    if (snapshot == null) return;
    _lastSnapshot = snapshot;

    final reason = _pressureReason(snapshot);
    if (reason == null) return;

    // A cooldown, and background sessions to give up, are both required. If
    // only the active account is warm there is nothing this class can do,
    // and saying so once is far better than reloading the user's page every
    // poll in the hope the number moves.
    final last = _lastPressureAction;
    if (last != null &&
        DateTime.now().difference(last) < AppConstants.pressureCooldown) {
      return;
    }
    if (_leastRecentlyUsedBackgroundId() == null) {
      _governor.log('$reason — nothing to free (only the active account)', snapshot);
      _lastPressureAction = DateTime.now();
      return;
    }

    _relievingPressure = true;
    try {
      await _runLocked(() => _freeBackgroundSessions(snapshot, reason));
    } finally {
      _relievingPressure = false;
      _lastPressureAction = DateTime.now();
    }
  }

  /// Returns why we should act, or null if everything is fine.
  ///
  /// Deliberately narrow. The old version treated "summed tree RSS over
  /// 420 MB" as an emergency, which on this app is simply its normal
  /// resting state.
  String? _pressureReason(MemorySnapshot snapshot) {
    final ratio = snapshot.systemAvailableRatio;
    if (ratio != null && ratio < AppConstants.systemLowMemoryRatio) {
      return 'machine low on memory (${(ratio * 100).toStringAsFixed(0)}% free)';
    }

    // A web process nearing WebKit's per-process kill threshold. Freeing
    // background accounts won't shrink the offender, but it does remove
    // competing processes and, if the offender IS a background account, it
    // is the direct fix.
    final warnBytes =
        (AppConstants.webProcessKillThresholdBytes *
                AppConstants.webProcessWarnRatio)
            .round();
    final biggest = snapshot.largestWebProcess;
    if (biggest != null && biggest.bytes >= warnBytes) {
      return 'web process ${biggest.pid} at ${biggest.mb.toStringAsFixed(0)} MB '
          '(WebKit kills at '
          '${(AppConstants.webProcessKillThresholdBytes / (1024 * 1024)).round()} MB)';
    }
    return null;
  }

  Future<void> _freeBackgroundSessions(
    MemorySnapshot snapshot,
    String reason,
  ) async {
    _governor.log('$reason — freeing background accounts', snapshot);

    // One round only: drop every background account that has been idle for
    // the grace period. Bounded work, no re-measure loop, no way to spiral.
    while (true) {
      final victim = _leastRecentlyUsedBackgroundId(
        minimumIdle: AppConstants.pressureIdleGrace,
      );
      if (victim == null) break;
      await _destroy(victim, reason: reason);
    }

    await Future<void>.delayed(AppConstants.memorySettleDelay);
    if (_disposed) return;
    final after = await _governor.snapshot();
    if (after != null) {
      _lastSnapshot = after;
      _governor.log('after freeing background accounts', after);
    }
  }

  /// LRU order comes from `_warm`'s insertion order (re-inserted on every
  /// acquire). The active account is never a candidate — it belongs to the
  /// user, not to the watchdog.
  String? _leastRecentlyUsedBackgroundId({Duration? minimumIdle}) {
    final now = DateTime.now();
    for (final id in _warm.keys) {
      if (id == _activeAccountId) continue;
      if (minimumIdle != null) {
        final since = _pausedSince[id];
        if (since != null && now.difference(since) < minimumIdle) continue;
      }
      return id;
    }
    return null;
  }

  Future<void> _destroy(String accountId, {required String reason}) async {
    final handle = _warm.remove(accountId);
    _pausedSince.remove(accountId);
    if (handle == null) return;
    await MemoryProfiler.logAround(
      'destroy session $accountId ($reason)',
      () async {
        try {
          await handle.unloadFromMemory();
        } catch (_) {}
        try {
          await handle.dispose();
        } catch (_) {}
      },
    );
  }

  Future<void> _sweepIdleSessions() async {
    if (_disposed) return;
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
      await _destroy(id, reason: 'idle >= ${_idleEvictionTimeout.inMinutes}m');
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

  Future<bool> _evictLeastRecentlyUsed() async {
    final lruId = _leastRecentlyUsedBackgroundId();
    if (lruId == null) return false;
    await _destroy(lruId, reason: 'LRU eviction (cap $_maxWarmSessions)');
    return true;
  }

  Future<void> evict(String accountId) {
    return _runLocked(() async {
      await _destroy(accountId, reason: 'explicit evict');
      if (_activeAccountId == accountId) _activeAccountId = null;
    });
  }

  Future<void> disposeAll() {
    return _runLocked(() async {
      for (final id in _warm.keys.toList(growable: false)) {
        await _destroy(id, reason: 'shutdown');
      }
      _warm.clear();
      _pausedSince.clear();
      _activeAccountId = null;
    });
  }

  void dispose() {
    _disposed = true;
    _idleSweepTimer.cancel();
    _activeReloadTimer.cancel();
    _memoryTimer?.cancel();
  }
}