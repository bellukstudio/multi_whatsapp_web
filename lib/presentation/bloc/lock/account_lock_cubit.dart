import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:multi_whatsapp_web/data/datasources/local/account_lock_local_datasource.dart';


/// Tracks which account ids currently have a password lock set, so
/// the UI can show a lock badge and react immediately after a
/// password is set/changed/removed — without touching the Isar
/// account schema at all.
class AccountLockCubit extends Cubit<Set<String>> {
  AccountLockCubit(this._dataSource) : super(const {}) {
    _load();
  }

  final AccountLockLocalDatasource _dataSource;

  /// Accounts that are locked RIGHT NOW for this running session — i.e.
  /// "Lock this account" was pressed while it was open, and it hasn't
  /// been unlocked again yet. This is intentionally separate from
  /// [state] (which only tracks whether a password exists at all) and
  /// is NOT persisted: it's a live, in-memory "curtain" over an
  /// already-open account, not the account's actual protection status.
  /// A fresh app launch always starts with nothing session-locked.
  final ValueNotifier<Set<String>> sessionLocked = ValueNotifier<Set<String>>(
    const {},
  );

  Future<void> _load() async {
    final ids = await _dataSource.getLockedAccounts();
    if (!isClosed) emit(ids);
  }

  bool isLocked(String accountId) => state.contains(accountId);

  bool isSessionLocked(String accountId) =>
      sessionLocked.value.contains(accountId);

  /// Immediately locks [accountId] for this session — used for "Lock
  /// this account" on the account that's currently open, without
  /// switching away from it first. No-op if the account has no
  /// password set yet, since there'd be nothing to unlock it with.
  bool lockNow(String accountId) {
    if (!isLocked(accountId)) return false;
    if (sessionLocked.value.contains(accountId)) return true;
    sessionLocked.value = {...sessionLocked.value, accountId};
    return true;
  }

  /// Clears the session lock for [accountId] — call after the user has
  /// re-entered the correct password.
  void unlockSession(String accountId) {
    if (!sessionLocked.value.contains(accountId)) return;
    final next = {...sessionLocked.value}..remove(accountId);
    sessionLocked.value = next;
  }

  /// Sets (or overwrites) the password for [accountId].
  Future<void> setPassword(String accountId, String password) async {
    await _dataSource.setPassword(accountId, password);
    if (!isClosed) emit({...state, accountId});
  }

  /// Removes the password lock for [accountId], if any is set.
  Future<void> removePassword(String accountId) async {
    await _dataSource.removePassword(accountId);
    if (!isClosed) {
      final next = {...state}..remove(accountId);
      emit(next);
    }
    // No password left to unlock it with, so it can't stay session-locked.
    unlockSession(accountId);
  }

  /// Verifies [password] against the stored hash for [accountId].
  /// Returns `true` when correct, or when the account has no
  /// password set at all.
  Future<bool> verifyPassword(String accountId, String password) {
    return _dataSource.verifyPassword(accountId, password);
  }

  @override
  Future<void> close() {
    sessionLocked.dispose();
    return super.close();
  }
}