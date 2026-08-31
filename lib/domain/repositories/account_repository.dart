import '../../core/constants/app_constants.dart';
import '../entities/account.dart';

abstract class AccountRepository {
  Stream<List<Account>> watchAccounts();

  Future<List<Account>> getAccounts();

  Future<Account> getAccountById(String id);

  Future<Account> addAccount({required String name});

  Future<void> renameAccount({required String id, required String newName});

  Future<void> logoutAccount(String id);

  Future<void> deleteAccount(String id);

  Future<void> updateStatus({
    required String id,
    required AccountConnectionStatus status,
  });

  Future<void> setActiveAccount(String id);

  Stream<String?> watchActiveAccountId();

  Future<void> reorderAccounts(List<String> orderedIds);
}
