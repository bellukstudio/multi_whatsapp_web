import '../entities/account.dart';
import '../repositories/account_repository.dart';

class AddAccount {
  AddAccount(this._repo);
  final AccountRepository _repo;

  Future<Account> call({required String name}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Account name cannot be empty');
    }
    return _repo.addAccount(name: trimmed);
  }
}
