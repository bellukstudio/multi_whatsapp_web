import 'package:isar_community/isar.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/account.dart';

part 'account_model.g.dart';

@collection
class AccountModel {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String accountId;

  late String name;

  @enumerated
  late AccountStatusDb status;

  late String sessionPath;
  late DateTime createdAt;
  DateTime? lastConnectedAt;
  int? avatarColorSeed;
  late int orderIndex;

  Account toEntity() => Account(
    id: accountId,
    name: name,
    status: status.toDomain(),
    sessionPath: sessionPath,
    createdAt: createdAt,
    lastConnectedAt: lastConnectedAt,
    avatarColorSeed: avatarColorSeed,
    orderIndex: orderIndex,
  );

  static AccountModel fromEntity(Account a) => AccountModel()
    ..accountId = a.id
    ..name = a.name
    ..status = AccountStatusDbX.fromDomain(a.status)
    ..sessionPath = a.sessionPath
    ..createdAt = a.createdAt
    ..lastConnectedAt = a.lastConnectedAt
    ..avatarColorSeed = a.avatarColorSeed
    ..orderIndex = a.orderIndex;
}

enum AccountStatusDb { connecting, connected, disconnected, loggedOut, error }

extension AccountStatusDbX on AccountStatusDb {
  AccountConnectionStatus toDomain() {
    switch (this) {
      case AccountStatusDb.connecting:
        return AccountConnectionStatus.connecting;
      case AccountStatusDb.connected:
        return AccountConnectionStatus.connected;
      case AccountStatusDb.disconnected:
        return AccountConnectionStatus.disconnected;
      case AccountStatusDb.loggedOut:
        return AccountConnectionStatus.loggedOut;
      case AccountStatusDb.error:
        return AccountConnectionStatus.error;
    }
  }

  static AccountStatusDb fromDomain(AccountConnectionStatus s) {
    switch (s) {
      case AccountConnectionStatus.connecting:
        return AccountStatusDb.connecting;
      case AccountConnectionStatus.connected:
        return AccountStatusDb.connected;
      case AccountConnectionStatus.disconnected:
        return AccountStatusDb.disconnected;
      case AccountConnectionStatus.loggedOut:
        return AccountStatusDb.loggedOut;
      case AccountConnectionStatus.error:
        return AccountStatusDb.error;
    }
  }
}
