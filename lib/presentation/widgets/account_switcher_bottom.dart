import 'package:flutter/material.dart';
import 'package:multi_whatsapp_web/core/constants/app_constants.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/account.dart';
import '../../domain/repositories/webview_adapter.dart';

class AccountSwitcherBottom extends StatelessWidget {
  const AccountSwitcherBottom({
    super.key,
    required this.accounts,
    required this.activeAccountId,
    required this.onSelect,
    required this.onAdd,
    required this.onContextMenu,
    this.activeSession,
  });

  final List<Account> accounts;
  final String? activeAccountId;
  final ValueChanged<Account> onSelect;
  final VoidCallback onAdd;
  final void Function(Account) onContextMenu;
  final WebViewSessionHandle? activeSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: outline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: accounts.length,
              itemBuilder: (context, i) {
                final account = accounts[i];
                return _AccountStripTile(
                  account: account,
                  selected: account.id == activeAccountId,
                  onTap: () => onSelect(account),
                  onLongPress: () => onContextMenu(account),
                );
              },
            ),
          ),
          Container(width: 1, height: 40, color: outline),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Tooltip(
              message: 'Add account',
              child: _StripActionButton(
                onTap: onAdd,
                icon: Icons.add_rounded,
                outlined: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StripActionButton extends StatelessWidget {
  const _StripActionButton({
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
          child: Icon(icon, size: 22, color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}

class _AccountStripTile extends StatelessWidget {
  const _AccountStripTile({
    required this.account,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Account account;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

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
    final stripBg = theme.colorScheme.surfaceContainerLow;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
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
                      border: Border.all(color: stripBg, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
