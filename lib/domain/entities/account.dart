import 'package:equatable/equatable.dart';

import '../../core/constants/app_constants.dart';

/// Domain entity for a single WhatsApp Web session (PRD §8-9).
///
/// This is intentionally platform-agnostic: it knows nothing about
/// WebView2 / WKWebView / WebKitGTK / flutter_inappwebview. Platform
/// specifics live behind [WebViewAdapter] in the data layer.
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

  /// Stable unique id (uuid v4), used as the WebView data-directory suffix
  /// / isolated data-store identifier (PRD §24) — never shown to the user.
  final String id;

  /// User-editable label (PRD §7 rename account).
  final String name;

  final AccountConnectionStatus status;

  /// Sandbox-relative storage path for this account's persisted session.
  /// Desktop: a free-standing folder under app storage.
  /// Mobile: an app-sandbox directory (PRD §8-9) — NEVER shown in UI
  /// per §17 / §25 (don't expose session path to end users).
  final String sessionPath;

  final DateTime createdAt;
  final DateTime? lastConnectedAt;

  /// Deterministic seed so the same account always gets the same avatar
  /// color across desktop sidebar and mobile switcher (PRD §6.1 / §6.2).
  final int? avatarColorSeed;

  /// Position in the account list, used by both the sidebar (desktop) and
  /// the bottom switcher / drawer (mobile) to keep ordering consistent.
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
