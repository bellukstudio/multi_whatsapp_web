import '../repositories/account_repository.dart';
import '../../core/constants/app_constants.dart';

class SwitchAccount {
  SwitchAccount(this._repo);
  final AccountRepository _repo;

  Future<void> call({
    required String accountId,
    required FormFactor formFactor,
  }) {
    return _repo.setActiveAccount(accountId);
  }
}
