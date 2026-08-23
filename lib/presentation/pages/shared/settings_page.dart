import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_constants.dart';
import '../../bloc/theme/theme_cubit.dart';

/// PRD §16/§17 Settings.
///
/// Session storage path is shown only on desktop and only ever as an
/// informational (non-editable, non-copyable-as-sensitive) detail — PRD
/// §17/§25 explicitly forbid exposing the raw session path on mobile.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.formFactor});

  final FormFactor formFactor;

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeCubit>().state;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(title: Text('Appearance'), dense: true),
          ListTile(
            title: const Text('System'),
            leading: Radio<AppThemeMode>(
              value: AppThemeMode.system,
              groupValue: themeMode,
              onChanged: (v) => context.read<ThemeCubit>().setMode(v!),
            ),
            onTap: () => context.read<ThemeCubit>().setMode(AppThemeMode.system),
          ),
          ListTile(
            title: const Text('Light'),
            leading: Radio<AppThemeMode>(
              value: AppThemeMode.light,
              groupValue: themeMode,
              onChanged: (v) => context.read<ThemeCubit>().setMode(v!),
            ),
            onTap: () => context.read<ThemeCubit>().setMode(AppThemeMode.light),
          ),
          ListTile(
            title: const Text('Dark'),
            leading: Radio<AppThemeMode>(
              value: AppThemeMode.dark,
              groupValue: themeMode,
              onChanged: (v) => context.read<ThemeCubit>().setMode(v!),
            ),
            onTap: () => context.read<ThemeCubit>().setMode(AppThemeMode.dark),
          ),
          const Divider(),
          if (formFactor == FormFactor.desktop) ...[
            const ListTile(title: Text('Storage'), dense: true),
            const ListTile(
              title: Text('Session storage location'),
              subtitle: Text('App support directory (per-account subfolders)'),
              // PRD §17: desktop MAY show the path; still avoid exposing
              // raw absolute paths with account-identifying uuids in
              // plain UI text — show a generic description here and put
              // the literal path behind an explicit "Reveal" action if
              // ever needed.
            ),
          ],
          const Divider(),
          ListTile(
            title: const Text('About'),
            subtitle: const Text(
              'Multi WhatsApp Web is an unofficial WhatsApp Web session '
              'manager. Not affiliated with WhatsApp/Meta. Using an '
              'unofficial client may carry account risk under WhatsApp\'s '
              'Terms of Service (see PRD §37).',
            ),
          ),
        ],
      ),
    );
  }
}
