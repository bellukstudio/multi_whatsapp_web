import 'package:flutter/material.dart';

/// Full-pane placeholder shown in place of the WebView when the
/// currently-open account has been locked mid-session (via "Lock this
/// account"). Whoever wires this up is responsible for having already
/// paused the native WebView surface (see `WebViewSessionHandle.
/// pauseRendering()`) before showing this — on Linux/Windows the real
/// webview is a separate native layer, so this widget alone would not
/// actually cover it.
class AccountLockedScreen extends StatelessWidget {
  const AccountLockedScreen({
    super.key,
    required this.accountName,
    required this.onUnlock,
  });

  final String accountName;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.lock_outline,
                size: 30,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '"$accountName" is locked',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Enter the password to keep using this account.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onUnlock,
              icon: const Icon(Icons.lock_open_outlined, size: 18),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
