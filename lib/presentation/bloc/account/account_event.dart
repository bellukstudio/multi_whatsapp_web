part of 'account_bloc.dart';

abstract class AccountEvent extends Equatable {
  const AccountEvent();
  @override
  List<Object?> get props => [];
}

class AccountsSubscriptionRequested extends AccountEvent {
  const AccountsSubscriptionRequested();
}

class _AccountsUpdated extends AccountEvent {
  const _AccountsUpdated(this.accounts);
  final List<Account> accounts;
  @override
  List<Object?> get props => [accounts];
}

class AccountAdded extends AccountEvent {
  const AccountAdded(this.name);
  final String name;
  @override
  List<Object?> get props => [name];
}

class AccountRenamed extends AccountEvent {
  const AccountRenamed({required this.id, required this.newName});
  final String id;
  final String newName;
  @override
  List<Object?> get props => [id, newName];
}

class AccountDeleted extends AccountEvent {
  const AccountDeleted(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

class AccountLoggedOut extends AccountEvent {
  const AccountLoggedOut(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}
