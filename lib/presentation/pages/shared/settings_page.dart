import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:multi_whatsapp_web/presentation/bloc/session/session_cubit.dart';

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
          // RadioGroup replaces the old per-Radio groupValue/onChanged
          // (deprecated since Flutter 3.32): the group now owns the
          // selected value and change callback, and each Radio below
          // only needs its own `value`.
          RadioGroup<AppThemeMode>(
            groupValue: themeMode,
            onChanged: (v) => context.read<ThemeCubit>().setMode(v!),
            child: Column(
              children: [
                ListTile(
                  title: const Text('System'),
                  leading: const Radio<AppThemeMode>(
                    value: AppThemeMode.system,
                  ),
                  onTap: () =>
                      context.read<ThemeCubit>().setMode(AppThemeMode.system),
                ),
                ListTile(
                  title: const Text('Light'),
                  leading: const Radio<AppThemeMode>(value: AppThemeMode.light),
                  onTap: () =>
                      context.read<ThemeCubit>().setMode(AppThemeMode.light),
                ),
                ListTile(
                  title: const Text('Dark'),
                  leading: const Radio<AppThemeMode>(value: AppThemeMode.dark),
                  onTap: () =>
                      context.read<ThemeCubit>().setMode(AppThemeMode.dark),
                ),
              ],
            ),
          ),
          const Divider(),
          if (formFactor == FormFactor.desktop) ...[
            const ListTile(title: Text('Storage'), dense: true),
            const ListTile(
              title: Text('Session storage location'),
              subtitle: Text('App support directory (per-account subfolders)'),
            ),
          ],
          if (formFactor == FormFactor.mobile) ...[
            const ListTile(title: Text('Tampilan'), dense: true),
            Builder(
              builder: (context) {
                final handle = context.read<SessionCubit>().mobileHandle;
                if (handle == null) {
                  return const ListTile(
                    title: Text('Mode Desktop'),
                    subtitle: Text('Buka salah satu akun terlebih dahulu'),
                    enabled: false,
                  );
                }
                return ValueListenableBuilder<bool>(
                  valueListenable: handle.desktopModeEnabled,
                  builder: (context, enabled, _) {
                    return SwitchListTile(
                      title: const Text('Mode Desktop'),
                      subtitle: const Text(
                        'Tampilkan WhatsApp Web seperti di komputer',
                      ),
                      value: enabled,
                      onChanged: (v) => handle.setDesktopMode(v),
                    );
                  },
                );
              },
            ),
            const Divider(),
          ],
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
