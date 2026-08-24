import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/webview_safe_overlay.dart';
import '../../../domain/entities/account.dart';
import '../../bloc/account/account_bloc.dart';
import '../../bloc/session/session_cubit.dart';
import '../../widgets/sidebar.dart';
import '../../widgets/webview_container.dart';
import '../shared/add_account_page.dart';
import '../shared/settings_page.dart';

/// PRD §6.1 desktop layout (connected/disconnected status footer removed
/// per request — no longer shown):
/// ┌─────────────────────────────────────────────────────┐
/// │ Multi WhatsApp Web                         ⚙        │
/// ├──────────────┬──────────────────────────────────────┤
/// │ Accounts     │            WhatsApp Web              │
/// │ + Add        │                                      │
/// │ 🟢 Personal  │                                      │
/// │ 🟢 Business  │                                      │
/// │ 🔴 Sales     │                                      │
/// └──────────────┴──────────────────────────────────────┘
class DashboardDesktopPage extends StatelessWidget {
  const DashboardDesktopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            icon: AppConstants.settingsIcon(),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const SettingsPage(formFactor: FormFactor.desktop),
              ),
            ),
          ),
        ],
      ),
      body: BlocBuilder<AccountBloc, AccountState>(
        builder: (context, accountState) {
          return BlocBuilder<SessionCubit, SessionState>(
            builder: (context, sessionState) {
              final activeMatches = accountState.accounts.where(
                (a) => a.id == sessionState.activeAccountId,
              );
              final activeAccount = activeMatches.isEmpty
                  ? null
                  : activeMatches.first;

              return Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Sidebar(
                          accounts: accountState.accounts,
                          activeAccountId: sessionState.activeAccountId,
                          activeSession: sessionState.handle,
                          onSelect: (a) =>
                              context.read<SessionCubit>().switchTo(a),
                          onAdd: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AddAccountPage(),
                            ),
                          ),
                          onRename: (a) => showOverlaySafely(
                            sessionState.handle,
                            () => _showRenameDialog(context, a.id, a.name),
                          ),
                          // onLogout: (a) {
                          //   context.read<SessionCubit>().releaseAccount(a.id);
                          //   context.read<AccountBloc>().add(
                          //     AccountLoggedOut(a.id),
                          //   );
                          // },
                          onDelete: (a) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              showOverlaySafely(
                                sessionState.handle,
                                () => _confirmDeleteAccount(context, a),
                              );
                            });
                          },
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: WebViewContainer(
                            account: activeAccount,
                            sessionState: sessionState,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Diubah jadi `return showDialog(...)` (sebelumnya dipanggil tanpa
  /// return) — showOverlaySafely butuh Future ini supaya tahu kapan
  /// dialog benar-benar tertutup sebelum memanggil resumeRendering().
  Future<void> _showRenameDialog(
    BuildContext context,
    String id,
    String currentName,
  ) {
    final controller = TextEditingController(text: currentName);
    return showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename account'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<AccountBloc>().add(
                AccountRenamed(id: id, newName: controller.text),
              );
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context, Account account) {
    return showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text(
          'This will remove "${account.name}" and delete its local session data. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(dialogContext, rootNavigator: true).pop();
              context.read<SessionCubit>().releaseAccount(account.id);
              context.read<AccountBloc>().add(AccountDeleted(account.id));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}