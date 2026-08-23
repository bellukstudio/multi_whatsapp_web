import '../entities/account.dart';
import '../repositories/account_repository.dart';

/// PRD §6: powers both the desktop sidebar list and the mobile
/// switcher/drawer list — same use case, two renderings.
class WatchAccounts {
  WatchAccounts(this._repo);
  final AccountRepository _repo;

  Stream<List<Account>> call() => _repo.watchAccounts();
}
