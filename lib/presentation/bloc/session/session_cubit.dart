import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/memory_profiler.dart';
import '../../../domain/entities/account.dart';
import '../../../domain/repositories/account_repository.dart';
import '../../../domain/repositories/webview_adapter.dart';
import 'session_pool_manager.dart';

part 'session_state.dart';

/// Manages the active WebView session(s) (PRD §6.2/§15/§26/§27).
///
/// - **Mobile**: strict single-session model. Only one
///   [WebViewSessionHandle] ever exists; switching accounts fully
///   unloads the previous one (§27 — mandatory since MVP).
/// - **Desktop**: backed by [SessionPoolManager], which keeps up to
///   [AppConstants.maxRecommendedDesktopSessions] warm at once, throttles
///   (pauses) inactive-but-warm ones, and LRU-evicts beyond the cap
///   (§26 — "10 akun: tidak crash, resource dimonitor").
///
/// Both paths funnel memory-sensitive operations through
/// [MemoryProfiler] so RAM regressions show up in logs during manual/CI
/// testing (see README §4 "Test dispose leak").
class SessionCubit extends Cubit<SessionState> {
  SessionCubit({
    required WebViewAdapter webViewAdapter,
    required AccountRepository accountRepository,
    required FormFactor formFactor,
    SessionPoolManager? poolManager,
  })  : _webViewAdapter = webViewAdapter,
        _accountRepository = accountRepository,
        _formFactor = formFactor,
        _pool = formFactor == FormFactor.desktop
            ? (poolManager ?? SessionPoolManager(webViewAdapter: webViewAdapter))
            : null,
        super(const SessionState());

  final WebViewAdapter _webViewAdapter;
  final AccountRepository _accountRepository;
  final FormFactor _formFactor;

  /// Only non-null on desktop — mobile deliberately has no multi-warm
  /// pool (§27).
  final SessionPoolManager? _pool;

  Future<void> switchTo(Account account) async {
    // IMPORTANT: activeAccountId must be set immediately (optimistically),
    // not only after the async work below succeeds. WebViewContainer keys
    // its entire render (empty/loading/error/ready) off whether an active
    // account can be resolved from this id — if we wait until success to
    // set it, a failure (or even just the loading phase) leaves
    // activeAccountId null, so the UI silently stays on the empty state
    // and tapping an account looks like it does nothing at all.
    emit(state.copyWith(
      status: ActiveSessionStatus.loading,
      activeAccountId: account.id,
      clearError: true,
    ));

    final WebViewSessionHandle handle;
    try {
      handle = _formFactor == FormFactor.desktop
          ? await _pool!.acquire(account)
          : await _switchMobile(account);
    } catch (e) {
      // A platform adapter refusing to create a session (e.g. Linux/iOS
      // before their §24 isolation PoC passes) must surface as an error
      // state, never as an unhandled exception that crashes the app.
      // activeAccountId is kept set (see note above) so the error is
      // actually shown instead of silently reverting to the empty state.
      emit(state.copyWith(
        status: ActiveSessionStatus.error,
        activeAccountId: account.id,
        errorMessage: e.toString(),
      ));
      return;
    }

    handle.statusStream.listen(
      (status) => _accountRepository.updateStatus(id: account.id, status: status),
      onError: (_) {}, // never let a status-stream error bubble unhandled
    );

    await _accountRepository.setActiveAccount(account.id);

    emit(state.copyWith(
      activeAccountId: account.id,
      status: ActiveSessionStatus.ready,
      handle: handle,
    ));
  }

  /// PRD §26/§27: on mobile, the previous handle is unloaded from memory
  /// (not just hidden) before the new one is created — this is the
  /// fundamental difference from desktop's keep-warm model, and it's
  /// mandatory since MVP, not a later optimization.
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

  /// PRD §11: called on app resume (mobile lifecycle `AppLifecycleState.
  /// resumed`) when we can't be sure the OS kept the WebView alive in the
  /// background. Shows "reconnecting" rather than assuming
  /// instant-connected.
  Future<void> handleAppResumed(Account activeAccount) async {
    if (_formFactor != FormFactor.mobile) return; // desktop: no-op, §14a

    emit(state.copyWith(status: ActiveSessionStatus.reconnecting, clearError: true));
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
      emit(state.copyWith(
        status: ActiveSessionStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  /// PRD §27: called on app backgrounded (mobile) to proactively free the
  /// WebView even before the OS forces it — more battery/RAM-friendly
  /// than waiting for OS suspension.
  Future<void> handleAppBackgrounded() async {
    if (_formFactor != FormFactor.mobile) return;
    if (state.handle == null) return;
    await MemoryProfiler.logAround(
      'unload mobile session on background',
      () => state.handle!.unloadFromMemory(),
    );
  }

  /// PRD §12: release pooled/mobile memory immediately on delete, rather
  /// than waiting for LRU pressure or the next background event.
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
    } else {
      await state.handle?.dispose();
    }
    return super.close();
  }
}
