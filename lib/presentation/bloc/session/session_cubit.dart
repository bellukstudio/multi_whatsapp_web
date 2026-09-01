import 'dart:io' show Platform;

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
  }) : _webViewAdapter = webViewAdapter,
       _accountRepository = accountRepository,
       _formFactor = formFactor,
       _pool = formFactor == FormFactor.desktop
           ? (poolManager ??
                 SessionPoolManager(
                   webViewAdapter: webViewAdapter,

                   maxWarmSessions: Platform.isWindows ? 1 : null,
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
    emit(
      state.copyWith(
        status: ActiveSessionStatus.loading,
        activeAccountId: account.id,
        clearError: true,
      ),
    );

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

  Future<WebViewSessionHandle> _switchMobile(Account account) async {
    if (state.handle != null) {
      await MemoryProfiler.logAround(
        'unload previous mobile session',
        () => state.handle!.unloadFromMemory(),
      );
      await state.handle!.dispose();
    }

    final handle = await MemoryProfiler.logAround(
      'create mobile session ${account.id}',
      () => _webViewAdapter.createOrResumeSession(
        accountId: account.id,
        sessionPath: account.sessionPath,
      ),
    );
    await handle.navigateToWhatsAppWeb();
    return handle;
  }

  /// Manually reload the currently active session's WebView in place.
  /// Reclaims memory WhatsApp Web has accumulated over a long, actively
  /// used session (decoded images/video, chat history in the JS heap,
  /// etc.) — this is an ordinary page reload, NOT a logout: cookies,
  /// localStorage, and the account's WhatsApp session token all live on
  /// disk (see LinuxWebKitPlatformView's per-account data directory) and
  /// survive it, so WhatsApp Web just re-renders from its own local
  /// state/service worker like a normal browser refresh.
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
        'reload mobile session on resume',
        () => _webViewAdapter.reloadFromPersistedStorage(
          accountId: activeAccount.id,
          sessionPath: activeAccount.sessionPath,
        ),
      );
      await handle.navigateToWhatsAppWeb();
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
      'unload mobile session on background',
      () => state.handle!.unloadFromMemory(),
    );
  }

  Future<void> releaseAccount(String accountId) async {
    if (_formFactor == FormFactor.desktop) {
      await _pool!.evict(accountId);
    } else if (state.activeAccountId == accountId && state.handle != null) {
      await state.handle!.unloadFromMemory();
      await state.handle!.dispose();
      emit(state.copyWith(clearHandle: true, activeAccountId: null));
    }
  }

  @override
  Future<void> close() async {
    if (_formFactor == FormFactor.desktop) {
      await _pool?.disposeAll();

      _pool?.dispose();
    } else {
      await state.handle?.dispose();
    }
    return super.close();
  }
}