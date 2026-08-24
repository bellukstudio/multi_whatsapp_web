import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/account.dart';
import 'account_tile.dart';

/// PRD §6.2 alternative: a drawer (☰) with the full account list as an
/// overlay, mirroring the desktop sidebar's content without being a
/// permanent panel. Complements — doesn't replace — the bottom switcher.
class AccountDrawer extends StatelessWidget {
  const AccountDrawer({
    super.key,
    required this.accounts,
    required this.activeAccountId,
    required this.onSelect,
    required this.onLongPress,
    required this.onSettings,
  });

  final List<Account> accounts;
  final String? activeAccountId;
  final ValueChanged<Account> onSelect;
  final void Function(Account) onLongPress;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const DrawerHeader(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text('Multi WhatsApp Web',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: accounts.length,
                itemBuilder: (context, i) {
                  final account = accounts[i];
                  return AccountTile(
                    account: account,
                    selected: account.id == activeAccountId,
                    onTap: () {
                      Navigator.pop(context);
                      onSelect(account);
                    },
                    onLongPress: () => onLongPress(account),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: AppConstants.settingsIcon(),
              title: const Text('Settings'),
              onTap: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}