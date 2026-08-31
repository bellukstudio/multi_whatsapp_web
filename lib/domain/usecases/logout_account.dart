import '../repositories/account_repository.dart';
import '../repositories/webview_adapter.dart';

class LogoutAccount {
  LogoutAccount(this._repo, this._webViewAdapter);

  final AccountRepository _repo;
  final WebViewAdapter _webViewAdapter;

  Future<void> call({required String id, required String sessionPath}) async {
    final handle = await _webViewAdapter.createOrResumeSession(
      accountId: id,
      sessionPath: sessionPath,
    );
    await handle.clearSessionData();
    await _repo.logoutAccount(id);
  }
}
