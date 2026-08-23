
import 'package:isar_community/isar.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/account.dart';

part 'account_model.g.dart';

/// Isar collection for persisted account metadata (PRD §19 Local Storage
/// Data Model). Only metadata lives here — actual WhatsApp Web session
/// data (cookies/localStorage/IndexedDB) is owned by the native WebView
/// engine's own isolated profile on disk (PRD §24), not by this DB.
@collection
class AccountModel {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String accountId; // uuid, matches Account.id

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

/// Mirrors [AccountConnectionStatus] but kept as its own DB-facing enum so
/// the domain enum can evolve without an Isar schema migration headache.
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
