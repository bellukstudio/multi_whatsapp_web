import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/webview_safe_overlay.dart';
import '../../bloc/account/account_bloc.dart';
import '../../bloc/session/session_cubit.dart';
import '../../widgets/account_switcher_bottom.dart';
import '../../widgets/webview_container.dart';
import '../shared/add_account_page.dart';
import '../shared/settings_page.dart';

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
      sessionCubit.handleAppResumed(activeAccount);
    } else if (state == AppLifecycleState.paused) {
      sessionCubit.handleAppBackgrounded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AccountBloc, AccountState>(
      builder: (context, accountState) {
        return BlocBuilder<SessionCubit, SessionState>(
          builder: (context, sessionState) {
            final activeMatches = accountState.accounts.where(
              (a) => a.id == sessionState.activeAccountId,
            );
            final activeAccount = activeMatches.isEmpty
                ? null
                : activeMatches.first;

            return Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    _MobileActiveAccountHeader(
                      account: activeAccount,
                      onOpenSettings: () => showOverlaySafely(
                        sessionState.handle,
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsPage(
                              formFactor: FormFactor.mobile,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: WebViewContainer(
                        account: activeAccount,
                        sessionState: sessionState,
                      ),
                    ),
                    AccountSwitcherBottom(
                      accounts: accountState.accounts,
                      activeAccountId: sessionState.activeAccountId,
                      activeSession: sessionState.handle,
                      onSelect: (a) => context.read<SessionCubit>().switchTo(a),
                      onAdd: () => showOverlaySafely(
                        sessionState.handle,
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AddAccountPage(),
                          ),
                        ),
                      ),
                      onContextMenu: (a) =>
                          _showAccountActions(context, a.id, a.name),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAccountActions(
    BuildContext context,
    String id,
    String name,
  ) async {
    final activeSession = context.read<SessionCubit>().state.handle;
    final isActive = context.read<SessionCubit>().state.activeAccountId == id;

    await showOverlaySafely(activeSession, () async {
      await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        isScrollControlled: false,
        builder: (sheetContext) => SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  name,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename'),
                onTap: () async {
                  Navigator.of(sheetContext, rootNavigator: true).pop();
                  await _showRenameDialog(context, id, name);
                },
              ),
              ListTile(
                enabled: isActive,
                leading: const Icon(Icons.refresh),
                title: const Text('Reload'),
                subtitle: isActive
                    ? null
                    : const Text('Buka akun ini dulu untuk reload'),
                onTap: !isActive
                    ? null
                    : () {
                        Navigator.of(sheetContext, rootNavigator: true).pop();
                        activeSession?.reload();
                      },
              ),

              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
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

  Future<void> _showRenameDialog(
    BuildContext context,
    String id,
    String currentName,
  ) async {
    final activeSession = context.read<SessionCubit>().state.handle;
    final controller = TextEditingController(text: currentName);
    await showOverlaySafely(
      activeSession,
      () => showDialog(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Rename account'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext, rootNavigator: true).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                context.read<AccountBloc>().add(
                  AccountRenamed(id: id, newName: controller.text),
                );
                Navigator.of(dialogContext, rootNavigator: true).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(
    BuildContext context,
    String id,
    String name,
  ) async {
    final activeSession = context.read<SessionCubit>().state.handle;
    await showOverlaySafely(
      activeSession,
      () => showDialog(
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
              onPressed: () =>
                  Navigator.of(dialogContext, rootNavigator: true).pop(),
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
      ),
    );
  }
}

class _MobileActiveAccountHeader extends StatelessWidget {
  const _MobileActiveAccountHeader({
    required this.account,
    required this.onOpenSettings,
  });

  final dynamic account;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 20, right: 6),
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
          IconButton(
            icon: AppConstants.settingsIcon(),
            onPressed: onOpenSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}
