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

  Future<void> _load() async {
    final ids = await _dataSource.getLockedAccounts();
    if (!isClosed) emit(ids);
  }

  bool isLocked(String accountId) => state.contains(accountId);

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
  }

  /// Verifies [password] against the stored hash for [accountId].
  /// Returns `true` when correct, or when the account has no
  /// password set at all.
  Future<bool> verifyPassword(String accountId, String password) {
    return _dataSource.verifyPassword(accountId, password);
  }
}