import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/di/injection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await configureDependencies();

  // PRD §6.1 vs §6.2: authoritative form factor, used for session
  // lifecycle rules (§27) — NOT re-derived from window size once set.
  final formFactor =
      (Platform.isAndroid || Platform.isIOS) ? FormFactor.mobile : FormFactor.desktop;

  // TODO (desktop only, PRD §18/§40): initialize window_manager +
  // tray_manager + launch_at_startup here, guarded by
  // `formFactor == FormFactor.desktop`.

  runApp(MultiWhatsAppWebApp(formFactor: formFactor));
}