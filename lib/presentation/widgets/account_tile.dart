import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/account.dart';
import 'status_badge.dart';

/// Shared visual for one account row/chip. Used by the desktop sidebar
/// list AND the mobile drawer list (PRD §6.1/§6.2 both list accounts with
/// name + status) — only the container around it differs.
class AccountTile extends StatelessWidget {
  const AccountTile({
    super.key,
    required this.account,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.dense = false,
  });

  final Account account;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress; // PRD §12: long-press context menu (mobile)
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.avatarColorFor(account.avatarColorSeed);
    return ListTile(
      dense: dense,
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      onTap: onTap,
      onLongPress: onLongPress,
      leading: CircleAvatar(
        backgroundColor: color,
        child: Text(
          account.name.isNotEmpty ? account.name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Text(account.name, overflow: TextOverflow.ellipsis),
      trailing: StatusBadge(status: account.status),
    );
  }
}
