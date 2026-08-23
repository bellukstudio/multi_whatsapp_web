import '../repositories/account_repository.dart';
import '../repositories/webview_adapter.dart';

/// PRD §12: logs an account out of WhatsApp Web (clears cookies /
/// localStorage / IndexedDB for that isolated profile) but keeps the
/// account entry so the user can re-scan a QR later.
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
