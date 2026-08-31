import 'dart:async';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/account.dart';
import '../../domain/repositories/account_repository.dart';
import '../datasources/local/account_local_datasource.dart';
import '../models/account_model.dart';

class AccountRepositoryImpl implements AccountRepository {
  AccountRepositoryImpl(this._local);

  final AccountLocalDataSource _local;

  final _activeAccountController = StreamController<String?>.broadcast();
  String? _activeAccountId;

  @override
  Stream<List<Account>> watchAccounts() {
    return _local.watchAll().map(
      (models) => models.map((m) => m.toEntity()).toList(),
    );
  }

  @override
  Future<List<Account>> getAccounts() async {
    final models = await _local.getAll();
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<Account> getAccountById(String id) async {
    final model = await _local.getById(id);
    if (model == null) {
      throw StateError('Account not found: $id');
    }
    return model.toEntity();
  }

  @override
  Future<Account> addAccount({required String name}) async {
    final model = await _local.create(name: name);
    return model.toEntity();
  }

  @override
  Future<void> renameAccount({
    required String id,
    required String newName,
  }) async {
    final model = await _local.getById(id);
    if (model == null) return;
    model.name = newName;
    await _local.update(model);
  }

  @override
  Future<void> logoutAccount(String id) async {
    final model = await _local.getById(id);
    if (model == null) return;
    model.status = AccountStatusDb.loggedOut;
    await _local.update(model);
  }

  @override
  Future<void> deleteAccount(String id) async {
    await _local.delete(id);
    if (_activeAccountId == id) {
      _activeAccountId = null;
      _activeAccountController.add(null);
    }
  }

  @override
  Future<void> updateStatus({
    required String id,
    required AccountConnectionStatus status,
  }) async {
    final model = await _local.getById(id);
    if (model == null) return;
    model.status = AccountStatusDbX.fromDomain(status);
    if (status == AccountConnectionStatus.connected) {
      model.lastConnectedAt = DateTime.now();
    }
    await _local.update(model);
  }

  @override
  Future<void> setActiveAccount(String id) async {
    _activeAccountId = id;
    _activeAccountController.add(id);
  }

  @override
  Stream<String?> watchActiveAccountId() => _activeAccountController.stream;

  @override
  Future<void> reorderAccounts(List<String> orderedIds) {
    return _local.reorder(orderedIds);
  }
}
