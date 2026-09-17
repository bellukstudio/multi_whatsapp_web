import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/memory_profiler.dart';
import '../../../data/datasources/webview/desktop/windows_webview_adapter.dart'
    show WebView2RuntimeMissingException;
import '../../../data/datasources/webview/mobile/mobile_webview_session_handle.dart';
import '../../../domain/entities/account.dart';
import '../../../domain/repositories/account_repository.dart';
import '../../../domain/repositories/webview_adapter.dart';
import 'session_pool_manager.dart';

part 'session_state.dart';

class SessionCubit extends Cubit<SessionState> {
  SessionCubit({
    required WebViewAdapter webViewAdapter,
    required AccountRepository accountRepository,
    required FormFactor formFactor,
    SessionPoolManager? poolManager,
    // Lock safety: SessionCubit used to always `resumeRendering()` any warm
    // account regardless of its lock state. This optional callback (default:
    // nothing is locked) tells it whether an account should stay hidden,
    // without coupling it to AccountLockCubit — normally filled with
    // `accountLockCubit.isSessionLocked`.
    bool Function(String accountId)? isAccountSessionLocked,
  }) : _webViewAdapter = webViewAdapter,
       _accountRepository = accountRepository,
       _formFactor = formFactor,
       _isAccountSessionLocked = isAccountSessionLocked,
       super(const SessionState()) {
    _pool = formFactor == FormFactor.desktop
        ? (poolManager ?? SessionPoolManager(webViewAdapter: webViewAdapter))
        : null;
  }

  final WebViewAdapter _webViewAdapter;
  final AccountRepository _accountRepository;
  final FormFactor _formFactor;
  final bool Function(String accountId)? _isAccountSessionLocked;

  late final SessionPoolManager? _pool;

  /// FIX (unbounded listener growth): `handle.statusStream.listen(...)` used
  /// to run on EVERY switch, including switches back to an already-warm
  /// handle, and nothing was ever cancelled. Ten switches between two
  /// accounts left ten live subscriptions on the same broadcast stream, each
  /// firing its own repository write on every status change — a slow leak of
  /// both memory and IO that grew for as long as the app stayed open. Now
  /// there is at most one subscription per account, cancelled when the
  /// session goes away.
  final Map<String, StreamSubscription<AccountConnectionStatus>> _statusSubs =
      {};

  Future<void> _switchLock = Future<void>.value();

  Future<void> switchTo(Account account) {
    final result = _switchLock.then((_) => _switchToLocked(account));
    _switchLock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _switchToLocked(Account account) async {
    final alreadyWarm = _formFactor == FormFactor.mobile
        ? _mobileWarm.containsKey(account.id)
        : (_pool?.isWarm(account.id) ?? false);

    if (!alreadyWarm) {
      emit(
        state.copyWith(
          status: ActiveSessionStatus.loading,
          activeAccountId: account.id,
          clearError: true,
        ),
      );
    }

    // Must stay hidden behind AccountLockedScreen even though we're
    // switching "to" it — don't let the pool auto-show its native view.
    final keepPaused = _isAccountSessionLocked?.call(account.id) ?? false;

    final WebViewSessionHandle handle;
    try {
      handle = _formFactor == FormFactor.desktop
          ? await _pool!.acquire(account, keepPaused: keepPaused)
          : await _switchMobile(account);
    } catch (e) {
      emit(
        state.copyWith(
          status: ActiveSessionStatus.error,
          activeAccountId: account.id,
          errorMessage: e.toString(),
          errorNeedsAppRestart:
              e is WebView2RuntimeMissingException &&
              e.isDispatcherQueueConflict,
        ),
      );
      return;
    }

    _listenToStatusOnce(account.id, handle);

    await _accountRepository.setActiveAccount(account.id);

    emit(
      state.copyWith(
        activeAccountId: account.id,
        status: ActiveSessionStatus.ready,
        handle: handle,
      ),
    );
  }

  void _listenToStatusOnce(String accountId, WebViewSessionHandle handle) {
    if (_statusSubs.containsKey(accountId)) return;
    _statusSubs[accountId] = handle.statusStream.listen(
      (status) =>
          _accountRepository.updateStatus(id: accountId, status: status),
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<void> _cancelStatusSub(String accountId) async {
    final sub = _statusSubs.remove(accountId);
    if (sub != null) await sub.cancel();
  }

  final Map<String, WebViewSessionHandle> _mobileWarm = {};

  Future<WebViewSessionHandle> _switchMobile(Account account) async {
    final existing = _mobileWarm[account.id];
    if (existing != null) {
      await _releaseOtherMobileSessions(keep: account.id);
      return existing;
    }

    // FIX (mobile OOM): PRD §27 mandates at most
    // [AppConstants.maxActiveWebViewsOnMobile] live WebView per app run, but
    // `_mobileWarm` was append-only — every account ever opened kept its
    // WebView (and, on Android, its whole `android:process` slot) alive for
    // the rest of the run. Four accounts was enough to sit around 700 MB.
    // Release the others BEFORE creating the new one, so the two never
    // overlap at peak.
    await _releaseOtherMobileSessions(keep: account.id);

    final handle = await MemoryProfiler.logAround(
      'create_mobile_session_${account.id}',
      () => _webViewAdapter.createOrResumeSession(
        accountId: account.id,
        sessionPath: account.sessionPath,
        accountName: account.name,
      ),
    );
    await handle.navigateToWhatsAppWeb();
    _mobileWarm[account.id] = handle;
    return handle;
  }

  Future<void> _releaseOtherMobileSessions({required String keep}) async {
    final stale = _mobileWarm.keys
        .where((id) => id != keep)
        .toList(growable: false);
    // Keep the most recent (maxActiveWebViewsOnMobile - 1) besides the one
    // being switched to; with the default of 1 that means releasing them all.
    final keepExtra = (AppConstants.maxActiveWebViewsOnMobile - 1)
        .clamp(0, stale.length)
        .toInt();
    final toRelease = stale.sublist(0, stale.length - keepExtra);

    for (final id in toRelease) {
      final handle = _mobileWarm.remove(id);
      if (handle == null) continue;
      await _cancelStatusSub(id);
      await MemoryProfiler.logAround('release_mobile_session_$id', () async {
        try {
          await handle.unloadFromMemory();
        } catch (_) {}
        try {
          await handle.dispose();
        } catch (_) {}
      });
    }
  }

  Future<void> reloadActive() async {
    if (_formFactor != FormFactor.desktop) return;
    final handle = state.handle;
    if (handle == null) return;
    await handle.reload();
  }

  Future<void> handleAppResumed(Account activeAccount) async {
    if (_formFactor != FormFactor.mobile) return;

    emit(
      state.copyWith(
        status: ActiveSessionStatus.reconnecting,
        clearError: true,
      ),
    );
    try {
      final handle = await MemoryProfiler.logAround(
        'reload_mobile_session_on_resume',
        () => _webViewAdapter.reloadFromPersistedStorage(
          accountId: activeAccount.id,
          sessionPath: activeAccount.sessionPath,
          accountName: activeAccount.name,
        ),
      );
      await handle.navigateToWhatsAppWeb();
      final stale = _mobileWarm[activeAccount.id];
      if (stale != null && !identical(stale, handle)) {
        await _cancelStatusSub(activeAccount.id);
        try {
          await stale.unloadFromMemory();
        } catch (_) {}
        await stale.dispose();
      }
      _mobileWarm[activeAccount.id] = handle;
      _listenToStatusOnce(activeAccount.id, handle);
      emit(state.copyWith(status: ActiveSessionStatus.ready, handle: handle));
    } catch (e) {
      emit(
        state.copyWith(
          status: ActiveSessionStatus.error,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> handleAppBackgrounded() async {
    if (_formFactor != FormFactor.mobile) return;
    if (state.handle == null) return;
    await MemoryProfiler.logAround(
      'unload_mobile_session_on_background',
      () => state.handle!.unloadFromMemory(),
    );
  }

  Future<void> releaseAccount(String accountId) async {
    await _cancelStatusSub(accountId);
    if (_formFactor == FormFactor.desktop) {
      await _pool!.evict(accountId);
    } else {
      final handle = _mobileWarm.remove(accountId);
      if (handle != null) {
        await handle.unloadFromMemory();
        await handle.dispose();
      }
      if (state.activeAccountId == accountId) {
        emit(state.copyWith(clearHandle: true, activeAccountId: null));
      }
    }
  }

  @override
  Future<void> close() async {
    for (final sub in _statusSubs.values) {
      await sub.cancel();
    }
    _statusSubs.clear();

    if (_formFactor == FormFactor.desktop) {
      await _pool?.disposeAll();
      _pool?.dispose();
    } else {
      for (final handle in _mobileWarm.values) {
        try {
          await handle.unloadFromMemory();
        } catch (_) {}
        await handle.dispose();
      }
      _mobileWarm.clear();
    }
    return super.close();
  }
}