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

/// PRD §6.1 desktop layout — REDESIGNED to a modern, minimal icon rail
/// (see [Sidebar]) with no top AppBar at all; the active account's name
/// now surfaces in a slim inline header above the WebView itself, so the
/// WebView gets nearly the full window instead of losing width to a wide
/// always-expanded sidebar *and* height to a Material AppBar.
///
/// ┌────┬──────────────────────────────────┐
/// │ +  │  Personal                    ⟳    │
/// │ 🟢A├──────────────────────────────────┤
/// │ 🟢B│                                   │
/// │ 🔴C│           WhatsApp Web           │
/// │    │                                   │
/// │ ⚙  │                                   │
/// └────┴──────────────────────────────────┘
///
/// IMPORTANT (bug fix): every navigation triggered from here — Settings,
/// Add Account, rename/delete dialogs — now goes through
/// [showOverlaySafely]. The native WebKitGTK/webview_windows surface is
/// composited *above* Flutter's own widget tree, so a bare
/// `Navigator.push` never actually hides it — the new page/dialog would
/// render underneath the still-visible WebView and look "cut off".
/// Previously only the account rename/delete flow did this; Settings and
/// Add Account did not, which was the reported bug.
class DashboardDesktopPage extends StatelessWidget {
  const DashboardDesktopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Sidebar(
                    accounts: accountState.accounts,
                    activeAccountId: sessionState.activeAccountId,
                    activeSession: sessionState.handle,
                    onSelect: (a) => context.read<SessionCubit>().switchTo(a),
                    onAdd: () => showOverlaySafely(
                      sessionState.handle,
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AddAccountPage(),
                        ),
                      ),
                    ),
                    onOpenSettings: () => showOverlaySafely(
                      sessionState.handle,
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const SettingsPage(formFactor: FormFactor.desktop),
                        ),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ActiveAccountHeader(account: activeAccount),
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

/// Slim inline header above the WebView — replaces the old full-width
/// Material AppBar. Just the active account's name (so you always know
/// which session you're looking at) plus a reload affordance; everything
/// else (adding accounts, settings) now lives in the rail instead of
/// competing for space up here.
class _ActiveAccountHeader extends StatelessWidget {
  const _ActiveAccountHeader({required this.account});

  final Account? account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              account?.name ?? AppConstants.appName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}