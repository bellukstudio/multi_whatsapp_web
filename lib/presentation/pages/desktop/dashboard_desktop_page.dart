import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/desktop_page_route.dart';
import '../../../core/utils/webview_safe_overlay.dart';
import '../../../domain/entities/account.dart';
import '../../bloc/account/account_bloc.dart';
import '../../bloc/lock/account_lock_cubit.dart';
import '../../bloc/session/session_cubit.dart';
import '../../widgets/account_lock_dialogs.dart';
import '../../widgets/account_locked_screen.dart';
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
                      onLockNow: activeAccount == null
                          ? null
                          : () => _handleLockNow(
                              context,
                              sessionState,
                              activeAccount,
                            ),
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
                            onLock: activeAccount == null
                                ? null
                                : () => _handleLockNow(
                                    context,
                                    sessionState,
                                    activeAccount,
                                  ),
                          ),
                          Expanded(
                            child: ValueListenableBuilder<Set<String>>(
                              valueListenable: context
                                  .watch<AccountLockCubit>()
                                  .sessionLocked,
                              builder: (context, lockedNow, _) {
                                if (activeAccount != null &&
                                    lockedNow.contains(activeAccount.id)) {
                                  return AccountLockedScreen(
                                    accountName: activeAccount.name,
                                    onUnlock: () => _handleUnlockNow(
                                      context,
                                      sessionState,
                                      activeAccount,
                                    ),
                                  );
                                }
                                return WebViewContainer(
                                  account: activeAccount,
                                  sessionState: sessionState,
                                );
                              },
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
      ),
    );
  }

  Future<void> _handleLockNow(
    BuildContext context,
    SessionState sessionState,
    Account account,
  ) async {
    final lockCubit = context.read<AccountLockCubit>();

    // No password set yet — nothing to lock it with. Ask the user to set
    // one first, then lock immediately once it's in place.
    if (!lockCubit.isLocked(account.id)) {
      await showOverlaySafely(
        sessionState.handle,
        () => showSetAccountPasswordDialog(
          context,
          accountId: account.id,
          accountName: account.name,
        ),
      );
      if (!lockCubit.isLocked(account.id)) return; // user cancelled
    }

    // Pause the native WebView surface FIRST — on Linux/Windows it's a
    // separate layer on top of Flutter, so the lock screen underneath
    // wouldn't actually be visible otherwise. This also returns
    // keyboard focus to Flutter (see webkit_multi_view_plugin.cc), so
    // the unlock dialog's password field is typeable right away.
    await sessionState.handle?.pauseRendering();
    lockCubit.lockNow(account.id);
  }

  Future<void> _handleUnlockNow(
    BuildContext context,
    SessionState sessionState,
    Account account,
  ) async {
    final unlocked = await showUnlockAccountDialog(
      context,
      accountId: account.id,
      accountName: account.name,
    );
    if (!unlocked) return;

    context.read<AccountLockCubit>().unlockSession(account.id);
    await sessionState.handle?.resumeRendering();
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
              context.read<AccountLockCubit>().removePassword(account.id);
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
    this.onLock,
  });

  final Account? account;
  final bool canReload;
  final VoidCallback onReload;
  final VoidCallback? onLock;

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
          if (onLock != null)
            IconButton(
              icon: const Icon(Icons.lock_outline, size: 20),
              tooltip: 'Lock this account now',
              onPressed: onLock,
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
