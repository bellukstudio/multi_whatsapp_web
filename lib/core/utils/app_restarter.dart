import 'dart:io';

/// Fully relaunches this app as a brand-new OS process, then exits the
/// current one.
///
/// This exists specifically for native, thread-affinitized state that can
/// NEVER be cleaned up from Dart alone — e.g. a WebView2
/// `DispatcherQueueController` left attached to the app's main thread
/// (see `WebView2RuntimeMissingException.isDispatcherQueueConflict` in
/// `windows_webview_adapter.dart`). Windows only allows one such object
/// per *thread*, for the lifetime of the *process* — not the Dart
/// isolate — so once one is orphaned there (e.g. because a previous
/// WebviewController's dispose() didn't finish before the app moved on,
/// or — during development — because Hot Restart re-runs `main()`
/// without ever killing the native process), the only guaranteed fix is
/// a fresh process.
///
/// NOTE for developers: this is NOT a substitute for avoiding Hot
/// Restart during webview_windows development. Hot Restart itself is
/// what orphans the DispatcherQueueController in the first place; if
/// you're iterating on webview-related code, prefer a full stop +
/// `flutter run` over Hot Restart to avoid hitting this path at all.
class AppRestarter {
  static bool _restarting = false;

  static bool get isRestarting => _restarting;

  /// Spawns a fresh, detached copy of this executable with the same
  /// arguments, then terminates the current process. Safe to call more
  /// than once — calls after the first are ignored (the process is about
  /// to die anyway).
  static Future<void> restart({List<String>? arguments}) async {
    if (!Platform.isWindows) {
      // Only Windows has the DispatcherQueueController failure mode this
      // exists for today.
      return;
    }
    if (_restarting) return;
    _restarting = true;

    try {
      await Process.start(
        Platform.resolvedExecutable,
        arguments ?? Platform.executableArguments,
        mode: ProcessStartMode.detached,
        workingDirectory: File(Platform.resolvedExecutable).parent.path,
      );
    } finally {
      // Whether or not the relaunch succeeded, this process must die —
      // limping along with a broken WebView2 dispatcher state (every
      // future session creation will fail identically) is worse than a
      // hard exit the user can reopen from a fresh double-click.
      exit(0);
    }
  }
}