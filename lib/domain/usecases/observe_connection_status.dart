import '../../core/constants/app_constants.dart';
import '../repositories/account_repository.dart';

class ObserveAccountStatuses {
  ObserveAccountStatuses(this._repo);
  final AccountRepository _repo;

  Stream<Map<String, AccountConnectionStatus>> call() {
    return _repo.watchAccounts().map(
      (accounts) => {for (final a in accounts) a.id: a.status},
    );
  }
}
