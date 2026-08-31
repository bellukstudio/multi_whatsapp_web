import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/desktop_page_route.dart';
import '../../../core/utils/webview_safe_overlay.dart';
import '../../../domain/entities/account.dart';
import '../../bloc/account/account_bloc.dart';
import '../../bloc/session/session_cubit.dart';
import '../../widgets/sidebar.dart';
import '../../widgets/webview_container.dart';
import '../shared/add_account_page.dart';
import '../shared/settings_page.dart';

class DashboardDesktopPage extends StatelessWidget {
  const DashboardDesktopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<AccountBloc, AccountState>(
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
                            () => Navigator.of(
                          context,
                        ).push(desktopPageRoute((_) => const AddAccountPage())),
                      ),
                      onOpenSettings: () => showOverlaySafely(
                        sessionState.handle,
                            () => Navigator.of(context).push(
                          desktopPageRoute(
                                (_) => const SettingsPage(
                              formFactor: FormFactor.desktop,
                            ),
                          ),
                        ),
                      ),
                      onRename: (a) => showOverlaySafely(
                        sessionState.handle,
                            () => _showRenameDialog(context, a.id, a.name),
                      ),

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
                          _ActiveAccountHeader(
                            account: activeAccount,
                            canReload: sessionState.handle != null,
                            onReload: () =>
                                context.read<SessionCubit>().reloadActive(),
                          ),
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
      )
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

class _ActiveAccountHeader extends StatelessWidget {
  const _ActiveAccountHeader({
    required this.account,
    required this.canReload,
    required this.onReload,
  });

  final Account? account;
  final bool canReload;
  final VoidCallback onReload;

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
          if (canReload)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip:
                  'Reload this account\n'
                  '(reclaims memory built up over a long session — '
                  'not a logout)',
              onPressed: onReload,
            ),
        ],
      ),
    );
  }
}