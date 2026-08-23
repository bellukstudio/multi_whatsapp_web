import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/account.dart';
import 'status_badge.dart';

/// PRD §6.2 mobile bottom account strip:
/// │ 🟢 P  🟢 B  🔴 S  ＋       │
///
/// Horizontally scrollable row of small avatar chips + a trailing "add"
/// button. Long-press opens the same actions sheet as the desktop
/// sidebar (PRD §12 — accessed via long-press on mobile instead of
/// right-click).
class AccountSwitcherBottom extends StatelessWidget {
  const AccountSwitcherBottom({
    super.key,
    required this.accounts,
    required this.activeAccountId,
    required this.onSelect,
    required this.onAdd,
    required this.onLongPress,
  });

  final List<Account> accounts;
  final String? activeAccountId;
  final ValueChanged<Account> onSelect;
  final VoidCallback onAdd;
  final void Function(Account) onLongPress;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: accounts.length,
              itemBuilder: (context, i) {
                final account = accounts[i];
                final selected = account.id == activeAccountId;
                return GestureDetector(
                  onTap: () => onSelect(account),
                  onLongPress: () => onLongPress(account),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor:
                                  AppTheme.avatarColorFor(account.avatarColorSeed),
                              child: Text(
                                account.name.isNotEmpty
                                    ? account.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            if (selected)
                              Positioned(
                                bottom: -2,
                                left: 12,
                                right: 12,
                                child: Container(height: 2, color: Theme.of(context).colorScheme.primary),
                              ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: StatusBadge(status: account.status, size: 10),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: onAdd,
            tooltip: 'Add account',
          ),
        ],
      ),
    );
  }
}
