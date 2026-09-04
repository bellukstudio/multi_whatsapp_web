import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/app_update_info.dart';

Future<void> _openUpdateUrl(String? url) async {
  if (url == null || url.isEmpty) return;
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// A dismissible "there's a newer version" reminder. "Nanti" calls
/// [onLater] (wired to `UpdateCubit.skipCurrentVersion` by the
/// caller) so this specific version doesn't nag again.
Future<void> showOptionalUpdateDialog(
  BuildContext context, {
  required AppUpdateInfo info,
  required String? currentVersion,
  required String? updateUrl,
  required VoidCallback onLater,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.system_update_alt_rounded),
      title: const Text('Update tersedia'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Versi ${info.latestVersion} sudah tersedia'
            '${currentVersion != null ? ' (kamu masih pakai $currentVersion)' : ''}.',
          ),
          if (info.releaseNotes != null && info.releaseNotes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              info.releaseNotes!,
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onLater();
          },
          child: const Text('Nanti'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await _openUpdateUrl(updateUrl);
          },
          child: const Text('Update Sekarang'),
        ),
      ],
    ),
  );
}

/// A non-dismissible "you must update" dialog for when the installed
/// version has dropped below `minSupportedVersion`. There is no
/// cancel/skip action and the back button/barrier can't close it —
/// the only way out is to actually update (and relaunch with a
/// version that passes the check).
Future<void> showMandatoryUpdateDialog(
  BuildContext context, {
  required AppUpdateInfo info,
  required String? currentVersion,
  required String? updateUrl,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.system_update_alt_rounded, color: Colors.red),
        title: const Text('Update wajib diperlukan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Versi kamu${currentVersion != null ? ' ($currentVersion)' : ''} '
              'sudah tidak didukung lagi. Update ke versi '
              '${info.latestVersion} untuk melanjutkan.',
            ),
            if (info.releaseNotes != null &&
                info.releaseNotes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                info.releaseNotes!,
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => _openUpdateUrl(updateUrl),
            child: const Text('Update Sekarang'),
          ),
        ],
      ),
    ),
  );
}
