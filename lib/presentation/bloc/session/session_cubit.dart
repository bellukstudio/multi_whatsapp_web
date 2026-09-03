import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/memory_profiler.dart';
import '../../../data/datasources/webview/desktop/windows_webview_adapter.dart'
    show WebView2RuntimeMissingException;
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
  }) : _webViewAdapter = webViewAdapter,
        _accountRepository = accountRepository,
        _formFactor = formFactor,
        _pool = formFactor == FormFactor.desktop
            ? (poolManager ??
            SessionPoolManager(
              webViewAdapter: webViewAdapter,
              // Windows no longer needs to be capped to 1 warm session:
              // the patched `flutter-webview-windows` plugin gives each
              // account its own concurrently-alive WebView2 environment
              // (see windows_webview_adapter.dart), so it can share the
              // same default cap as macOS/Linux.
            ))
            : null,
        super(const SessionState());

  final WebViewAdapter _webViewAdapter;
  final AccountRepository _accountRepository;
  final FormFactor _formFactor;

  final SessionPoolManager? _pool;

  Future<void> _switchLock = Future<void>.value();

  Future<void> switchTo(Account account) {
    final result = _switchLock.then((_) => _switchToLocked(account));
    _switchLock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _switchToLocked(Account account) async {
    final alreadyWarmMobile =
        _formFactor == FormFactor.mobile &&
            _mobileWarm.containsKey(account.id);

    if (!alreadyWarmMobile) {
      emit(
        state.copyWith(
          status: ActiveSessionStatus.loading,
          activeAccountId: account.id,
          clearError: true,
        ),
      );
    }

    final WebViewSessionHandle handle;
    try {
      handle = _formFactor == FormFactor.desktop
          ? await _pool!.acquire(account)
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

    handle.statusStream.listen(
          (status) =>
          _accountRepository.updateStatus(id: account.id, status: status),
      onError: (_) {},
    );

    await _accountRepository.setActiveAccount(account.id);

    emit(
      state.copyWith(
        activeAccountId: account.id,
        status: ActiveSessionStatus.ready,
        handle: handle,
      ),
    );
  }

  final Map<String, WebViewSessionHandle> _mobileWarm = {};

  Future<WebViewSessionHandle> _switchMobile(Account account) async {
    final existing = _mobileWarm[account.id];
    if (existing != null) {
      return existing;
    }

    final handle = await MemoryProfiler.logAround(
      'create_mobile_session_${account.id}',
          () => _webViewAdapter.createOrResumeSession(
        accountId: account.id,
        sessionPath: account.sessionPath,
      ),
    );
    await handle.navigateToWhatsAppWeb();
    _mobileWarm[account.id] = handle;
    return handle;
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
        ),
      );
      await handle.navigateToWhatsAppWeb();
      final stale = _mobileWarm[activeAccount.id];
      if (stale != null && !identical(stale, handle)) {
        await stale.dispose();
      }
      _mobileWarm[activeAccount.id] = handle;
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
    if (_formFactor == FormFactor.desktop) {
      await _pool?.disposeAll();

      _pool?.dispose();
    } else {
      for (final handle in _mobileWarm.values) {
        await handle.dispose();
      }
      _mobileWarm.clear();
    }
    return super.close();
  }
}