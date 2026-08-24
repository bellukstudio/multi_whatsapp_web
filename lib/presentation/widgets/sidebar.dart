import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/webview_safe_overlay.dart';
import '../../domain/entities/account.dart';
import '../../domain/repositories/webview_adapter.dart';
import 'status_badge.dart';

/// PRD §6.1 desktop sidebar:
/// ┌──────────────┐
/// │ Accounts     │
/// │ + Add        │
/// │ 🟢 Personal  │
/// │ 🟢 Business  │
/// │ 🔴 Sales     │
/// └──────────────┘
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.accounts,
    required this.activeAccountId,
    required this.onSelect,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    // required this.onLogout,
    this.activeSession,
  });

  final List<Account> accounts;
  final String? activeAccountId;
  final ValueChanged<Account> onSelect;
  final VoidCallback onAdd;
  final void Function(Account) onRename;
  final void Function(Account) onDelete;
  // final void Function(Account) onLogout;
  final WebViewSessionHandle? activeSession;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Accounts', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: accounts.length,
              itemBuilder: (context, i) {
                final account = accounts[i];
                return ListTile(
                  selected: account.id == activeAccountId,
                  selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
                  onTap: () => onSelect(account),
                  onLongPress: () => _showContextMenu(context, account),
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.avatarColorFor(account.avatarColorSeed),
                    child: Text(
                      account.name.isNotEmpty ? account.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(account.name, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // StatusBadge(status: account.status),
                      PopupMenuButton<String>(
                        tooltip: 'Account actions',
                        onSelected: (value) {
                          switch (value) {
                            case 'rename':
                              onRename(account);
                              break;
                            // case 'logout':
                            //   onLogout(account);
                            //   break;
                            case 'delete':
                              onDelete(account);
                              break;
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          // PopupMenuItem(value: 'logout', child: Text('Logout')),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context, Account account) {
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
  });

  final Account account;
  final VoidCallback onRename;
  // final VoidCallback onLogout;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename'),
            onTap: () {
              Navigator.pop(context);
              onRename();
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Reload'),
            onTap: () => Navigator.pop(context),
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
