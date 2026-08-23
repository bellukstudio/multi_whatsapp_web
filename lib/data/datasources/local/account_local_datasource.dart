import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/account_model.dart';

/// Owns the Isar instance + raw CRUD for [AccountModel]. This is the only
/// place in the app that talks Isar directly — everything above this
/// (repository impl) works with domain [Account] entities.
class AccountLocalDataSource {
  AccountLocalDataSource(this._isar);

  final Isar _isar;
  final _uuid = const Uuid();

  static Future<AccountLocalDataSource> open() async {
    final dir = await getApplicationSupportDirectory();
    final isar = await Isar.open(
      [AccountModelSchema],
      directory: dir.path,
      name: 'multi_whatsapp_web',
    );
    return AccountLocalDataSource(isar);
  }

  Stream<List<AccountModel>> watchAll() {
    return _isar.accountModels
        .where()
        .sortByOrderIndex()
        .watch(fireImmediately: true);
  }

  Future<List<AccountModel>> getAll() =>
      _isar.accountModels.where().sortByOrderIndex().findAll();

  Future<AccountModel?> getById(String accountId) =>
      _isar.accountModels.filter().accountIdEqualTo(accountId).findFirst();

  /// PRD §7/§9: creates the metadata row AND reserves a fresh, never-reused
  /// uuid used as the WebView isolation key (PRD §24/§25) — this id is the
  /// thing that must never collide across accounts, unlike [name] which is
  /// just a user-facing label.
  Future<AccountModel> create({required String name}) async {
    final existingCount = await _isar.accountModels.count();
    final model = AccountModel()
      ..accountId = _uuid.v4()
      ..name = name
      ..status = AccountStatusDb.disconnected
      ..sessionPath = 'sessions/${_uuid.v4()}' // relative; resolved by
      // the WebView adapter into a real sandbox/app-support path per
      // platform (desktop: free folder; mobile: app sandbox, PRD §8-9).
      ..createdAt = DateTime.now()
      ..orderIndex = existingCount;

    await _isar.writeTxn(() => _isar.accountModels.put(model));
    return model;
  }

  Future<void> update(AccountModel model) async {
    await _isar.writeTxn(() => _isar.accountModels.put(model));
  }

  Future<void> delete(String accountId) async {
    await _isar.writeTxn(
      () => _isar.accountModels.filter().accountIdEqualTo(accountId).deleteAll(),
    );
  }

  Future<void> reorder(List<String> orderedIds) async {
    await _isar.writeTxn(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        final m = await _isar.accountModels
            .filter()
            .accountIdEqualTo(orderedIds[i])
            .findFirst();
        if (m != null) {
          m.orderIndex = i;
          await _isar.accountModels.put(m);
        }
      }
    });
  }
}
