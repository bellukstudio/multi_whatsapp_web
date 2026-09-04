import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firedart/auth/firebase_auth.dart';
import 'package:firedart/auth/token_store.dart';
import 'package:firedart/firestore/firestore.dart';
import 'package:flutter/material.dart';
import 'package:multi_whatsapp_web/firebase_options.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/di/injection.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const projectId = 'bellukstudio-8abde';
  const apiKey = 'AIzaSyC8Af_VMaF5eIILu3v_mDGaPsd_AYulqX8';

  // Initialize Authentication
  FirebaseAuth.initialize(apiKey, VolatileStore());
  // Sign in anonymously so firedart's Firestore client has a valid
  // session — without this, any Firestore call throws
  // SignedOutException.
  await FirebaseAuth.instance.signInAnonymously();

  if (!Platform.isLinux) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  Firestore.initialize(projectId);
  await configureDependencies();

  final formFactor = (Platform.isAndroid || Platform.isIOS)
      ? FormFactor.mobile
      : FormFactor.desktop;

  runApp(MultiWhatsAppWebApp(formFactor: formFactor));
}