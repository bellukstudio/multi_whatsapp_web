import '../../core/constants/app_constants.dart';
import '../entities/account.dart';

/// Domain-facing contract for account CRUD + status streaming.
///
/// PRD §10: "Domain/business logic (Account Manager, Session Manager)
/// tetap platform-agnostic." Nothing here mentions WebView, WebView2,
/// WKWebView, etc. — those live behind [WebViewAdapter].
abstract class AccountRepository {
  /// All accounts, ordered per [Account.orderIndex] (PRD §6.1 / §6.2).
  Stream<List<Account>> watchAccounts();

  Future<List<Account>> getAccounts();

  Future<Account> getAccountById(String id);

  /// Creates a new account entry + provisions an isolated session
  /// directory for it (PRD §7 Add Account, §24 isolation).
  Future<Account> addAccount({required String name});

  Future<void> renameAccount({required String id, required String newName});

  /// PRD §12: logs the account out of WhatsApp Web but keeps the account
  /// entry (so the user can re-scan a QR code later) — different from
  /// [deleteAccount].
  Future<void> logoutAccount(String id);

  /// PRD §12: removes the account entirely, including its isolated
  /// session storage (PRD §25 — must not leave orphaned session data).
  Future<void> deleteAccount(String id);

  /// PRD §13: updates in-memory + persisted connection status. Called by
  /// the WebView adapter layer when it observes WhatsApp Web's connection
  /// state changing.
  Future<void> updateStatus({
    required String id,
    required AccountConnectionStatus status,
  });

  /// PRD §6.2 / §15: only one account may be "active" (foregrounded
  /// WebView) at a time on mobile. Desktop MVP also keeps a single active
  /// view (split/grid is a future desktop-only feature, §15).
  Future<void> setActiveAccount(String id);

  Stream<String?> watchActiveAccountId();

  /// PRD §6 reorder support (drag in sidebar / drawer), optional for MVP
  /// but kept in the contract so UI can call it without a data-layer
  /// migration later.
  Future<void> reorderAccounts(List<String> orderedIds);
}
