part of 'account_bloc.dart';

abstract class AccountEvent extends Equatable {
  const AccountEvent();
  @override
  List<Object?> get props => [];
}

/// Fired once on startup to attach to the [WatchAccounts] stream
/// (PRD §5 First Launch / auto restore session).
class AccountsSubscriptionRequested extends AccountEvent {
  const AccountsSubscriptionRequested();
}

/// Internal event: a new snapshot arrived from the repository stream.
class _AccountsUpdated extends AccountEvent {
  const _AccountsUpdated(this.accounts);
  final List<Account> accounts;
  @override
  List<Object?> get props => [accounts];
}

/// PRD §7 Add account.
class AccountAdded extends AccountEvent {
  const AccountAdded(this.name);
  final String name;
  @override
  List<Object?> get props => [name];
}

/// PRD §7/§12 Rename account.
class AccountRenamed extends AccountEvent {
  const AccountRenamed({required this.id, required this.newName});
  final String id;
  final String newName;
  @override
  List<Object?> get props => [id, newName];
}

/// PRD §12 Delete account.
class AccountDeleted extends AccountEvent {
  const AccountDeleted(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

/// PRD §12 Logout account (keeps the entry, clears session data).
class AccountLoggedOut extends AccountEvent {
  const AccountLoggedOut(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}
