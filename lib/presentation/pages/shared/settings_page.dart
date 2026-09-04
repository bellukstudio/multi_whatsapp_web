import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:multi_whatsapp_web/presentation/bloc/session/session_cubit.dart';

import '../../../core/constants/app_constants.dart';
import '../../bloc/theme/theme_cubit.dart';
import '../../bloc/update/update_cubit.dart';
import '../../widgets/update_reminder_dialogs.dart';

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
            const Divider(),
          ],

          const ListTile(title: Text('Updates'), dense: true),
          BlocConsumer<UpdateCubit, UpdateState>(
            listenWhen: (previous, current) =>
                previous.status != current.status &&
                current.status != UpdateStatus.checking,
            listener: (context, state) async {
              final cubit = context.read<UpdateCubit>();
              switch (state.status) {
                case UpdateStatus.upToDate:
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Kamu sudah pakai versi terbaru.'),
                    ),
                  );
                case UpdateStatus.available:
                  if (state.info != null) {
                    await showOptionalUpdateDialog(
                      context,
                      info: state.info!,
                      currentVersion: state.currentVersion,
                      updateUrl: cubit.updateUrlForThisPlatform(),
                      onLater: () => cubit.skipCurrentVersion(),
                    );
                  }
                case UpdateStatus.required:
                  if (state.info != null) {
                    await showMandatoryUpdateDialog(
                      context,
                      info: state.info!,
                      currentVersion: state.currentVersion,
                      updateUrl: cubit.updateUrlForThisPlatform(),
                    );
                  }
                case UpdateStatus.initial:
                case UpdateStatus.checking:
                  break;
              }
            },
            builder: (context, state) {
              final checking = state.status == UpdateStatus.checking;
              return ListTile(
                leading: checking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt_rounded),
                title: const Text('Check for Updates'),
                subtitle: state.currentVersion != null
                    ? Text('Versi saat ini: ${state.currentVersion}')
                    : null,
                onTap: checking
                    ? null
                    : () => context.read<UpdateCubit>().checkForUpdate(),
              );
            },
          ),
          const Divider(),

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

