import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:multi_whatsapp_web/data/datasources/local/account_lock_local_datasource.dart';

class AccountLockCubit extends Cubit<Set<String>> {
  AccountLockCubit(this._dataSource) : super(const {}) {
    _load();
  }

  final AccountLockLocalDatasource _dataSource;

  final ValueNotifier<Set<String>> sessionLocked = ValueNotifier<Set<String>>(
    const {},
  );

  final Set<String> _unlockedThisSession = {};

  Future<void> _load() async {
    final ids = await _dataSource.getLockedAccounts();
    if (!isClosed) emit(ids);
  }

  bool isLocked(String accountId) => state.contains(accountId);

  bool isSessionLocked(String accountId) =>
      sessionLocked.value.contains(accountId);

  void ensureLockedIfNeeded(String accountId) {
    if (!isLocked(accountId)) return;
    if (_unlockedThisSession.contains(accountId)) return;
    if (sessionLocked.value.contains(accountId)) return;
    sessionLocked.value = {...sessionLocked.value, accountId};
  }

  bool lockNow(String accountId) {
    if (!isLocked(accountId)) return false;
    if (sessionLocked.value.contains(accountId)) return true;
    sessionLocked.value = {...sessionLocked.value, accountId};

    _unlockedThisSession.remove(accountId);
    return true;
  }

  void unlockSession(String accountId) {
    _unlockedThisSession.add(accountId);
    if (!sessionLocked.value.contains(accountId)) return;
    final next = {...sessionLocked.value}..remove(accountId);
    sessionLocked.value = next;
  }

  Future<void> setPassword(String accountId, String password) async {
    await _dataSource.setPassword(accountId, password);
    if (!isClosed) emit({...state, accountId});
  }

  Future<void> removePassword(String accountId) async {
    await _dataSource.removePassword(accountId);
    if (!isClosed) {
      final next = {...state}..remove(accountId);
      emit(next);
    }
    unlockSession(accountId);
    _unlockedThisSession.remove(accountId);
  }

  Future<bool> verifyPassword(String accountId, String password) {
    return _dataSource.verifyPassword(accountId, password);
  }

  @override
  Future<void> close() {
    sessionLocked.dispose();
    return super.close();
  }
}
