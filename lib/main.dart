import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/di/injection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await configureDependencies();

  final formFactor = (Platform.isAndroid || Platform.isIOS)
      ? FormFactor.mobile
      : FormFactor.desktop;

  runApp(MultiWhatsAppWebApp(formFactor: formFactor));
}
