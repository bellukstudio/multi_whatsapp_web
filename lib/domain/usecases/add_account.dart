import '../entities/account.dart';
import '../repositories/account_repository.dart';

/// PRD §7 Add WhatsApp Account.
///
/// Note: the actual QR code is rendered *inside* the isolated WebView by
/// web.whatsapp.com itself once navigation happens — this use case only
/// creates the account record + reserves an isolated session slot. The
/// presentation layer is responsible for then requesting a
/// [WebViewSessionHandle] via the WebView adapter and navigating it.
class AddAccount {
  AddAccount(this._repo);
  final AccountRepository _repo;

  Future<Account> call({required String name}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Account name cannot be empty');
    }
    return _repo.addAccount(name: trimmed);
  }
}
