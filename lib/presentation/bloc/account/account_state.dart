part of 'account_bloc.dart';

enum AccountsStatus { initial, loading, ready, failure }

class AccountState extends Equatable {
  const AccountState({
    this.status = AccountsStatus.initial,
    this.accounts = const [],
    this.errorMessage,
  });

  final AccountsStatus status;
  final List<Account> accounts;
  final String? errorMessage;

  /// PRD §6.1 footer: "Status: N Connected / M Disconnected".
  int get connectedCount =>
      accounts.where((a) => a.status == AccountConnectionStatus.connected).length;

  int get disconnectedCount => accounts.length - connectedCount;

  AccountState copyWith({
    AccountsStatus? status,
    List<Account>? accounts,
    String? errorMessage,
  }) {
    return AccountState(
      status: status ?? this.status,
      accounts: accounts ?? this.accounts,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, accounts, errorMessage];
}
