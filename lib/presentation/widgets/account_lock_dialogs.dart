import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/lock/account_lock_cubit.dart';

Future<bool> showUnlockAccountDialog(
  BuildContext context, {
  required String accountId,
  required String accountName,
}) async {
  final cubit = context.read<AccountLockCubit>();
  final controller = TextEditingController();
  bool obscure = true;
  String? error;
  bool checking = false;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> submit() async {
            if (controller.text.isEmpty) return;
            setState(() {
              checking = true;
              error = null;
            });
            final ok = await cubit.verifyPassword(accountId, controller.text);
            if (!dialogContext.mounted) return;
            if (ok) {
              Navigator.of(dialogContext).pop(true);
            } else {
              setState(() {
                checking = false;
                error = 'Incorrect password';
              });
            }
          }

          return AlertDialog(
            title: Text('Unlock "$accountName"'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('This account is protected by a password.'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: obscure,
                  autofocus: true,
                  enabled: !checking,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    errorText: error,
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: checking
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: checking ? null : submit,
                child: checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Unlock'),
              ),
            ],
          );
        },
      );
    },
  );

  return result ?? false;
}

Future<void> showSetAccountPasswordDialog(
  BuildContext context, {
  required String accountId,
  required String accountName,
}) {
  final cubit = context.read<AccountLockCubit>();
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      String? error;
      bool obscure = true;
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> submit() async {
            if (passwordController.text.isEmpty) {
              setState(() => error = 'Password cannot be empty');
              return;
            }
            if (passwordController.text != confirmController.text) {
              setState(() => error = 'Passwords do not match');
              return;
            }
            await cubit.setPassword(accountId, passwordController.text);
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          }

          return AlertDialog(
            title: Text('Set password for "$accountName"'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: passwordController,
                  obscureText: obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    errorText: error,
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: submit, child: const Text('Save')),
            ],
          );
        },
      );
    },
  );
}

Future<void> showChangeAccountPasswordDialog(
  BuildContext context, {
  required String accountId,
  required String accountName,
}) {
  final cubit = context.read<AccountLockCubit>();
  final currentController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      String? error;
      bool checking = false;
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> submit() async {
            if (currentController.text.isEmpty) {
              setState(() => error = 'Enter your current password');
              return;
            }
            if (newController.text.isEmpty) {
              setState(() => error = 'New password cannot be empty');
              return;
            }
            if (newController.text != confirmController.text) {
              setState(() => error = 'New passwords do not match');
              return;
            }
            setState(() {
              checking = true;
              error = null;
            });
            final ok = await cubit.verifyPassword(
              accountId,
              currentController.text,
            );
            if (!dialogContext.mounted) return;
            if (!ok) {
              setState(() {
                checking = false;
                error = 'Current password is incorrect';
              });
              return;
            }
            await cubit.setPassword(accountId, newController.text);
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          }

          return AlertDialog(
            title: Text('Change password for "$accountName"'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentController,
                  obscureText: true,
                  autofocus: true,
                  enabled: !checking,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newController,
                  obscureText: true,
                  enabled: !checking,
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  enabled: !checking,
                  decoration: InputDecoration(
                    labelText: 'Confirm new password',
                    errorText: error,
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: checking
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: checking ? null : submit,
                child: checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> showRemoveAccountPasswordDialog(
  BuildContext context, {
  required String accountId,
  required String accountName,
}) {
  final cubit = context.read<AccountLockCubit>();
  final currentController = TextEditingController();

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      String? error;
      bool checking = false;
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> submit() async {
            if (currentController.text.isEmpty) {
              setState(() => error = 'Enter the current password');
              return;
            }
            setState(() {
              checking = true;
              error = null;
            });
            final ok = await cubit.verifyPassword(
              accountId,
              currentController.text,
            );
            if (!dialogContext.mounted) return;
            if (!ok) {
              setState(() {
                checking = false;
                error = 'Incorrect password';
              });
              return;
            }
            await cubit.removePassword(accountId);
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          }

          return AlertDialog(
            title: Text('Remove password from "$accountName"'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the current password to remove the lock from '
                  'this account.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: currentController,
                  obscureText: true,
                  autofocus: true,
                  enabled: !checking,
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    errorText: error,
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: checking
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: checking ? null : submit,
                child: checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Remove'),
              ),
            ],
          );
        },
      );
    },
  );
}
