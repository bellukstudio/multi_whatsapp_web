import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/webview_safe_overlay.dart';
import '../../domain/entities/account.dart';
import '../../domain/repositories/webview_adapter.dart';

/// PRD §6.1 desktop sidebar — REDESIGNED as a slim icon rail instead of
/// the previous always-expanded 260px name list. Rationale: on smaller
/// windows the old sidebar competed hard with the WebView for width and
/// felt intrusive; a narrow rail (avatars + tooltips, like Slack's
/// workspace switcher) gives the same account-switching function in a
/// fraction of the space and reads as more modern/minimal.
///
/// ┌────┬──────────────────────────────────┐
/// │ +  │                                   │
/// │ 🟢A│           WhatsApp Web            │
/// │ 🟢B│                                   │
/// │ 🔴C│                                   │
/// │    │                                   │
/// │ ⚙  │                                   │
/// └────┴──────────────────────────────────┘
///
/// Settings now lives at the bottom of the rail (see [onOpenSettings])
/// instead of a top AppBar action — this also fixes a real bug: opening
/// Settings via a plain AppBar IconButton did a bare `Navigator.push`,
/// which never hid the native WebView overlay, so the new Settings page
/// rendered *underneath* it and looked "cut off". Every navigation this
/// rail triggers goes through [showOverlaySafely] so the native view is
/// paused/hidden first, exactly like the existing account-actions sheet
/// already did.
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
    // required this.onLogout,
    this.activeSession,
  });

  final List<Account> accounts;
  final String? activeAccountId;
  final ValueChanged<Account> onSelect;
  final VoidCallback onAdd;
  final void Function(Account) onRename;
  final void Function(Account) onDelete;
  final VoidCallback onOpenSettings;
  // final void Function(Account) onLogout;
  final WebViewSessionHandle? activeSession;

  static const double railWidth = 76;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

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
                        onTap: () => onSelect(account),
                        onContextMenu: () => _showContextMenu(context, account),
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
              icon: AppConstants.settingsIcon().icon ?? Icons.settings_rounded,
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context, Account account) {
    final isActive = account.id == activeAccountId;
    showOverlaySafely(
      activeSession,
      () => showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        builder: (_) => _AccountActionsSheet(
          account: account,
          onRename: () => onRename(account),
          // onLogout: () => onLogout(account),
          onDelete: () => onDelete(account),
          onReload: isActive ? () => activeSession?.reload() : null,
        ),
      ),
    );
  }
}

/// Small circular icon button used for the Add and Settings rail slots.
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

/// One account avatar in the rail: rounded-square selection state (à la
/// Slack), a small connection-status dot, tooltip with the full name
/// (since the name text itself no longer fits in a narrow rail), and
/// right-click (desktop) / long-press (touch) for rename/delete.
class _AccountRailTile extends StatelessWidget {
  const _AccountRailTile({
    required this.account,
    required this.selected,
    required this.onTap,
    required this.onContextMenu,
  });

  final Account account;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onContextMenu;

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
    // required this.onLogout,
    required this.onDelete,
    required this.onReload,
  });

  final Account account;
  final VoidCallback onRename;
  // final VoidCallback onLogout;
  final VoidCallback onDelete;

  /// Null when [account] isn't the currently active/open account — reload
  /// only makes sense for the one account that actually has a live
  /// WebView session right now.
  final VoidCallback? onReload;

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
          // ListTile(
          //   leading: const Icon(Icons.logout),
          //   title: const Text('Logout'),
          //   onTap: () {
          //     Navigator.pop(context);
          //     onLogout();
          //   },
          // ),
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