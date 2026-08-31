import '../repositories/account_repository.dart';

class DeleteAccount {
  DeleteAccount(this._repo);
  final AccountRepository _repo;

  Future<void> call(String id) => _repo.deleteAccount(id);
}
