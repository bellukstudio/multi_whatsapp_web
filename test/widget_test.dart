import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:multi_whatsapp_web/core/constants/app_constants.dart';
import 'package:multi_whatsapp_web/presentation/bloc/theme/theme_cubit.dart';
import 'package:multi_whatsapp_web/presentation/pages/shared/settings_page.dart';

void main() {
  testWidgets('settings page renders without native plugin setup', (tester) async {
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => ThemeCubit(),
        child: const MaterialApp(
          home: SettingsPage(formFactor: FormFactor.desktop),
        ),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
  });
}
