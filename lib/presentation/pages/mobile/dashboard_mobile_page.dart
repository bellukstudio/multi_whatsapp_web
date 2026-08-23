import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/webview_safe_overlay.dart';
import '../../bloc/account/account_bloc.dart';
import '../../bloc/session/session_cubit.dart';
import '../../widgets/account_drawer.dart';
import '../../widgets/account_switcher_bottom.dart';
import '../../widgets/webview_container.dart';
import '../shared/add_account_page.dart';
import '../shared/settings_page.dart';

/// PRD §6.2 mobile layout:
/// ┌───────────────────────────┐
/// │ ☰  Personal          ⚙   │
/// ├───────────────────────────┤
/// │                            │
/// │      WhatsApp Web          │
/// │      (active account)      │
/// │                            │
/// ├───────────────────────────┤
/// │ 🟢 P  🟢 B  🔴 S  ＋       │
/// └───────────────────────────┘
///
/// Wraps a [WidgetsBindingObserver] to implement PRD §11/§14a lifecycle
/// handling: on resume, tell [SessionCubit] to reload from persisted
/// storage rather than assume the WebView survived backgrounding; on
/// pause, optionally proactively unload it (§27).
class DashboardMobilePage extends StatefulWidget {
  const DashboardMobilePage({super.key});

  @override
  State<DashboardMobilePage> createState() => _DashboardMobilePageState();
}

class _DashboardMobilePageState extends State<DashboardMobilePage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final accountState = context.read<AccountBloc>().state;
    final sessionCubit = context.read<SessionCubit>();
    final activeId = sessionCubit.state.activeAccountId;
    if (activeId == null) return;

    final matches = accountState.accounts.where((a) => a.id == activeId);
    if (matches.isEmpty) return;
    final activeAccount = matches.first;

    if (state == AppLifecycleState.resumed) {
      // PRD §11: don't assume in-memory continuity.
      sessionCubit.handleAppResumed(activeAccount);
    } else if (state == AppLifecycleState.paused) {
      // PRD §27: proactive unload (mandatory strategy on mobile).
      sessionCubit.handleAppBackgrounded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AccountBloc, AccountState>(
      builder: (context, accountState) {
        return BlocBuilder<SessionCubit, SessionState>(
          builder: (context, sessionState) {
            final activeMatches = accountState.accounts
                .where((a) => a.id == sessionState.activeAccountId);
            final activeAccount = activeMatches.isEmpty ? null : activeMatches.first;

            return Scaffold(
              appBar: AppBar(
                title: Text(activeAccount?.name ?? AppConstants.appName),
                actions: [
                  IconButton(
                    icon: AppConstants.settingsIcon(),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const SettingsPage(formFactor: FormFactor.mobile),
                      ),
                    ),
                  ),
                ],
              ),
              drawer: AccountDrawer(
                accounts: accountState.accounts,
                activeAccountId: sessionState.activeAccountId,
                onSelect: (a) => context.read<SessionCubit>().switchTo(a),
                onLongPress: (a) => _showAccountActions(context, a.id, a.name),
                onSettings: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsPage(formFactor: FormFactor.mobile),
                    ),
                  );
                },
              ),
              body: WebViewContainer(account: activeAccount, sessionState: sessionState),
              bottomNavigationBar: AccountSwitcherBottom(
                accounts: accountState.accounts,
                activeAccountId: sessionState.activeAccountId,
                onSelect: (a) => context.read<SessionCubit>().switchTo(a),
                onAdd: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddAccountPage()),
                ),
                onLongPress: (a) => _showAccountActions(context, a.id, a.name),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAccountActions(BuildContext context, String id, String name) async {
    final activeSession = context.read<SessionCubit>().state.handle;
    await showOverlaySafely(activeSession, () async {
      await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: false,
        builder: (sheetContext) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename'),
                onTap: () async {
                  Navigator.of(sheetContext, rootNavigator: true).pop();
                  await _showRenameDialog(context, id, name);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.of(sheetContext, rootNavigator: true).pop();
                  context.read<SessionCubit>().releaseAccount(id);
                  context.read<AccountBloc>().add(AccountLoggedOut(id));
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.of(sheetContext, rootNavigator: true).pop();
                  await _confirmDeleteAccount(context, id, name);
                },
              ),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _showRenameDialog(BuildContext context, String id, String currentName) async {
    final activeSession = context.read<SessionCubit>().state.handle;
    final controller = TextEditingController(text: currentName);
    await showOverlaySafely(activeSession, () => showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename account'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context
                  .read<AccountBloc>()
                  .add(AccountRenamed(id: id, newName: controller.text));
              Navigator.of(dialogContext, rootNavigator: true).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ));
  }

  Future<void> _confirmDeleteAccount(BuildContext context, String id, String name) async {
    final activeSession = context.read<SessionCubit>().state.handle;
    await showOverlaySafely(activeSession, () => showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text(
          'This will remove "$name" and delete its local session data. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(dialogContext, rootNavigator: true).pop();
              context.read<SessionCubit>().releaseAccount(id);
              context.read<AccountBloc>().add(AccountDeleted(id));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    ));
  }
}
