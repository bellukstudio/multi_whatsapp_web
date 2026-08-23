import '../../core/constants/app_constants.dart';
import '../repositories/account_repository.dart';

/// PRD §13: real-time connected/disconnected status shown next to each
/// account in the sidebar (desktop) and account strip (mobile), plus the
/// aggregate "N Connected / M Disconnected" footer (§6.1).
class ObserveAccountStatuses {
  ObserveAccountStatuses(this._repo);
  final AccountRepository _repo;

  Stream<Map<String, AccountConnectionStatus>> call() {
    return _repo.watchAccounts().map(
          (accounts) => {
            for (final a in accounts) a.id: a.status,
          },
        );
  }
}
