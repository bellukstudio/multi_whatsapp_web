import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/account.dart';
import '../../../domain/usecases/add_account.dart';
import '../../../domain/usecases/delete_account.dart';
import '../../../domain/usecases/get_accounts.dart';
import '../../../domain/usecases/logout_account.dart';
import '../../../domain/usecases/rename_account.dart';

part 'account_event.dart';
part 'account_state.dart';

class AccountBloc extends Bloc<AccountEvent, AccountState> {
  AccountBloc({
    required WatchAccounts watchAccounts,
    required AddAccount addAccount,
    required RenameAccount renameAccount,
    required DeleteAccount deleteAccount,
    required LogoutAccount logoutAccount,
  }) : _watchAccounts = watchAccounts,
       _addAccount = addAccount,
       _renameAccount = renameAccount,
       _deleteAccount = deleteAccount,
       _logoutAccount = logoutAccount,
       super(const AccountState()) {
    on<AccountsSubscriptionRequested>(_onSubscriptionRequested);
    on<_AccountsUpdated>(_onAccountsUpdated);
    on<AccountAdded>(_onAccountAdded);
    on<AccountRenamed>(_onAccountRenamed);
    on<AccountDeleted>(_onAccountDeleted);
    on<AccountLoggedOut>(_onAccountLoggedOut);
  }

  final WatchAccounts _watchAccounts;
  final AddAccount _addAccount;
  final RenameAccount _renameAccount;
  final DeleteAccount _deleteAccount;
  final LogoutAccount _logoutAccount;

  StreamSubscription<List<Account>>? _sub;

  Future<void> _onSubscriptionRequested(
    AccountsSubscriptionRequested event,
    Emitter<AccountState> emit,
  ) async {
    emit(state.copyWith(status: AccountsStatus.loading));
    await _sub?.cancel();
    await emit.forEach<List<Account>>(
      _watchAccounts(),
      onData: (accounts) =>
          state.copyWith(status: AccountsStatus.ready, accounts: accounts),
      onError: (error, __) => state.copyWith(
        status: AccountsStatus.failure,
        errorMessage: error.toString(),
      ),
    );
  }

  void _onAccountsUpdated(_AccountsUpdated event, Emitter<AccountState> emit) {
    emit(
      state.copyWith(status: AccountsStatus.ready, accounts: event.accounts),
    );
  }

  Future<void> _onAccountAdded(
    AccountAdded event,
    Emitter<AccountState> emit,
  ) async {
    try {
      await _addAccount(name: event.name);
    } catch (e) {
      emit(state.copyWith(status: AccountsStatus.failure, errorMessage: '$e'));
    }
  }

  Future<void> _onAccountRenamed(
    AccountRenamed event,
    Emitter<AccountState> emit,
  ) async {
    await _renameAccount(id: event.id, newName: event.newName);
  }

  Future<void> _onAccountDeleted(
    AccountDeleted event,
    Emitter<AccountState> emit,
  ) async {
    await _deleteAccount(event.id);
  }

  Future<void> _onAccountLoggedOut(
    AccountLoggedOut event,
    Emitter<AccountState> emit,
  ) async {
    final account = state.accounts.firstWhere((a) => a.id == event.id);
    await _logoutAccount(id: event.id, sessionPath: account.sessionPath);
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
