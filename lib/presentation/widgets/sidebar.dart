import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/webview_safe_overlay.dart';
import '../../domain/entities/account.dart';
import '../../domain/repositories/webview_adapter.dart';
import '../bloc/lock/account_lock_cubit.dart';
import 'account_lock_dialogs.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.accounts,
    required this.activeAccountId,
    required this.onSelect,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onOpenSettings,

    this.activeSession,
    this.onLockNow,
  });

  final List<Account> accounts;
  final String? activeAccountId;
  final ValueChanged<Account> onSelect;
  final VoidCallback onAdd;
  final void Function(Account) onRename;
  final void Function(Account) onDelete;
  final VoidCallback onOpenSettings;

  final WebViewSessionHandle? activeSession;

  /// Locks the CURRENTLY OPEN account immediately. Only offered in the
  /// context menu of the account that is actually active — passed in
  /// from outside because only the dashboard page knows how to pause
  /// the native WebView surface for it.
  final VoidCallback? onLockNow;

  static const double railWidth = 76;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

    return BlocBuilder<AccountLockCubit, Set<String>>(
      builder: (context, lockedIds) {
        return Container(
          width: railWidth,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(right: BorderSide(color: outline)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 14),
              Tooltip(
                message: 'Add account',
                waitDuration: const Duration(milliseconds: 400),
                child: _RailButton(
                  onTap: onAdd,
                  icon: Icons.add_rounded,
                  outlined: true,
                ),
              ),
              const SizedBox(height: 10),
              Divider(height: 1, indent: 18, endIndent: 18, color: outline),
              Expanded(
                child: accounts.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        itemCount: accounts.length,
                        itemBuilder: (context, i) {
                          final account = accounts[i];
                          return _AccountRailTile(
                            account: account,
                            selected: account.id == activeAccountId,
                            locked: lockedIds.contains(account.id),
                            onTap: () => _handleTileTap(context, account),
                            onContextMenu: () =>
                                _showContextMenu(context, account),
                          );
                        },
                      ),
              ),
              Divider(height: 1, indent: 18, endIndent: 18, color: outline),
              const SizedBox(height: 10),
              Tooltip(
                message: 'Settings',
                waitDuration: const Duration(milliseconds: 400),
                child: _RailButton(
                  onTap: onOpenSettings,
                  icon:
                      AppConstants.settingsIcon().icon ??
                      Icons.settings_rounded,
                ),
              ),
              const SizedBox(height: 14),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleTileTap(BuildContext context, Account account) async {
    final lockCubit = context.read<AccountLockCubit>();
    if (lockCubit.isLocked(account.id)) {
      final unlocked = await showUnlockAccountDialog(
        context,
        accountId: account.id,
        accountName: account.name,
      );
      if (!unlocked) return;
    }
    onSelect(account);
  }

  void _showContextMenu(BuildContext context, Account account) {
    final isActive = account.id == activeAccountId;
    final isLocked = context.read<AccountLockCubit>().isLocked(account.id);
    showOverlaySafely(
      activeSession,
      () => showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        builder: (_) => _AccountActionsSheet(
          account: account,
          isLocked: isLocked,
          onRename: () => onRename(account),
          onDelete: () => onDelete(account),
          onReload: isActive ? () => activeSession?.reload() : null,
          onSetPassword: () => showOverlaySafely(
            activeSession,
            () => showSetAccountPasswordDialog(
              context,
              accountId: account.id,
              accountName: account.name,
            ),
          ),
          onChangePassword: () => showOverlaySafely(
            activeSession,
            () => showChangeAccountPasswordDialog(
              context,
              accountId: account.id,
              accountName: account.name,
            ),
          ),
          onRemovePassword: () => showOverlaySafely(
            activeSession,
            () => showRemoveAccountPasswordDialog(
              context,
              accountId: account.id,
              accountName: account.name,
            ),
          ),
          onLockNow: isActive ? onLockNow : null,
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.onTap,
    required this.icon,
    this.outlined = false,
  });

  final VoidCallback onTap;
  final IconData icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: outlined
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.55),
                    width: 1.4,
                  )
                : null,
          ),
          child: Icon(
            icon,
            size: 22,
            color: outlined
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _AccountRailTile extends StatelessWidget {
  const _AccountRailTile({
    required this.account,
    required this.selected,
    required this.onTap,
    required this.onContextMenu,
    this.locked = false,
  });

  final Account account;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onContextMenu;
  final bool locked;

  Color _statusColor(ColorScheme scheme) {
    switch (account.status) {
      case AccountConnectionStatus.connected:
        return const Color(0xFF25D366);
      case AccountConnectionStatus.connecting:
        return const Color(0xFFF4A259);
      case AccountConnectionStatus.disconnected:
      case AccountConnectionStatus.loggedOut:
        return scheme.outline;
      case AccountConnectionStatus.error:
        return scheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarColor = AppTheme.avatarColorFor(account.avatarColorSeed);
    final railBg = theme.colorScheme.surfaceContainerLow;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
      child: Tooltip(
        message: account.name,
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          onSecondaryTap: onContextMenu,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onLongPress: onContextMenu,
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: selected
                      ? theme.colorScheme.primaryContainer
                      : Colors.transparent,
                ),
                padding: const EdgeInsets.all(4),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: avatarColor,
                        child: Text(
                          account.name.isNotEmpty
                              ? account.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusColor(theme.colorScheme),
                          border: Border.all(color: railBg, width: 2),
                        ),
                      ),
                    ),
                    if (locked)
                      Positioned(
                        left: -3,
                        top: -3,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: railBg,
                          ),
                          child: Icon(
                            Icons.lock,
                            size: 10,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountActionsSheet extends StatelessWidget {
  const _AccountActionsSheet({
    required this.account,
    required this.onRename,
    required this.onDelete,
    required this.onReload,
    this.isLocked = false,
    this.onSetPassword,
    this.onChangePassword,
    this.onRemovePassword,
    this.onLockNow,
  });

  final Account account;
  final VoidCallback onRename;

  final VoidCallback onDelete;

  final VoidCallback? onReload;

  final bool isLocked;
  final VoidCallback? onSetPassword;
  final VoidCallback? onChangePassword;
  final VoidCallback? onRemovePassword;

  /// Locks this account (which must currently be the open/active one)
  /// right away. Null when this account isn't the active one.
  final VoidCallback? onLockNow;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Wrap(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              account.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () {
              Navigator.pop(context);
              onRename();
            },
          ),
          ListTile(
            enabled: onReload != null,
            leading: const Icon(Icons.refresh),
            title: const Text('Reload'),
            subtitle: onReload == null
                ? const Text('Open this account first to reload it')
                : null,
            onTap: onReload == null
                ? null
                : () {
                    Navigator.pop(context);
                    onReload!();
                  },
          ),
          ListTile(
            enabled: onLockNow != null,
            leading: const Icon(Icons.lock_clock_outlined),
            title: const Text('Lock Now'),
            subtitle: onLockNow == null
                ? const Text('Open this account first to lock it')
                : null,
            onTap: onLockNow == null
                ? null
                : () {
                    Navigator.pop(context);
                    onLockNow!();
                  },
          ),
          if (isLocked) ...[
            ListTile(
              leading: const Icon(Icons.lock_reset_outlined),
              title: const Text('Change Password'),
              onTap: () {
                Navigator.pop(context);
                onChangePassword?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_open_outlined),
              title: const Text('Remove Password'),
              onTap: () {
                Navigator.pop(context);
                onRemovePassword?.call();
              },
            ),
          ] else
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Set Password'),
              onTap: () {
                Navigator.pop(context);
                onSetPassword?.call();
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
        ],
      ),
    );
  }
}
