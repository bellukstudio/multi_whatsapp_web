import '../entities/account.dart';
import '../repositories/account_repository.dart';

class WatchAccounts {
  WatchAccounts(this._repo);
  final AccountRepository _repo;

  Stream<List<Account>> call() => _repo.watchAccounts();
}
