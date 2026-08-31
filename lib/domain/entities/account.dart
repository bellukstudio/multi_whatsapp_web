import 'package:equatable/equatable.dart';

import '../../core/constants/app_constants.dart';

class Account extends Equatable {
  const Account({
    required this.id,
    required this.name,
    required this.status,
    required this.sessionPath,
    required this.createdAt,
    this.lastConnectedAt,
    this.avatarColorSeed,
    this.orderIndex = 0,
  });

  final String id;

  final String name;

  final AccountConnectionStatus status;

  final String sessionPath;

  final DateTime createdAt;
  final DateTime? lastConnectedAt;

  final int? avatarColorSeed;

  final int orderIndex;

  bool get isConnected => status == AccountConnectionStatus.connected;

  Account copyWith({
    String? name,
    AccountConnectionStatus? status,
    String? sessionPath,
    DateTime? lastConnectedAt,
    int? avatarColorSeed,
    int? orderIndex,
  }) {
    return Account(
      id: id,
      name: name ?? this.name,
      status: status ?? this.status,
      sessionPath: sessionPath ?? this.sessionPath,
      createdAt: createdAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      avatarColorSeed: avatarColorSeed ?? this.avatarColorSeed,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    status,
    sessionPath,
    createdAt,
    lastConnectedAt,
    avatarColorSeed,
    orderIndex,
  ];
}
