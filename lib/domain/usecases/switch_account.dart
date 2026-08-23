import '../repositories/account_repository.dart';
import '../../core/constants/app_constants.dart';

/// PRD §6 / §15 Switch account.
///
/// Desktop MVP: single active view (split/grid is a future desktop-only
/// feature). Mobile: single active view is the ONLY option — switching
/// unloads the previous WebView from memory (PRD §26/§27) and may show a
/// brief loading state while the new one is (re)initialized from
/// persisted storage, unlike the desktop's "<1s" target which assumes an
/// already-loaded session.
class SwitchAccount {
  SwitchAccount(this._repo);
  final AccountRepository _repo;

  Future<void> call({
    required String accountId,
    required FormFactor formFactor,
  }) {
    // formFactor is accepted explicitly so callers/tests can reason about
    // which UX contract applies, even though the repository call itself
    // is the same — the *consequence* (unload vs keep-warm) is handled by
    // the presentation-layer session controller, not here.
    return _repo.setActiveAccount(accountId);
  }
}
