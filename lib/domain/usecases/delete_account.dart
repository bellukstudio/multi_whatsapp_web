import '../repositories/account_repository.dart';

/// PRD §12: removes the account and its isolated session storage
/// entirely (PRD §25 — no orphaned session data left on disk).
class DeleteAccount {
  DeleteAccount(this._repo);
  final AccountRepository _repo;

  Future<void> call(String id) => _repo.deleteAccount(id);
}
