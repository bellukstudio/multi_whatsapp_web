import '../repositories/account_repository.dart';

class RenameAccount {
  RenameAccount(this._repo);
  final AccountRepository _repo;

  Future<void> call({required String id, required String newName}) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Account name cannot be empty');
    }
    return _repo.renameAccount(id: id, newName: trimmed);
  }
}
