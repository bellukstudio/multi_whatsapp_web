import 'dart:io';

class AppRestarter {
  static bool _restarting = false;

  static bool get isRestarting => _restarting;

  static Future<void> restart({List<String>? arguments}) async {
    if (!Platform.isWindows) {
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
      exit(0);
    }
  }
}
