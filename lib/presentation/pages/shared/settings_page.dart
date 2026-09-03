import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:multi_whatsapp_web/presentation/bloc/session/session_cubit.dart';

import '../../../core/constants/app_constants.dart';
import '../../bloc/theme/theme_cubit.dart';

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

          ListTile(
            title: const Text('About'),
            subtitle: const Text(
              'Multi WhatsApp Web is an unofficial WhatsApp Web session '
              'manager. Not affiliated with WhatsApp/Meta. Using an '
              'unofficial client may carry account risk under WhatsApp\'s '
              'Terms of Service',
            ),
          ),
        ],
      ),
    );
  }
}
