import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/constants/app_constants.dart';
import 'core/di/injection.dart';
import 'core/theme/app_theme.dart';
import 'domain/repositories/account_repository.dart';
import 'domain/repositories/webview_adapter.dart';
import 'domain/usecases/add_account.dart';
import 'domain/usecases/delete_account.dart';
import 'domain/usecases/get_accounts.dart';
import 'domain/usecases/logout_account.dart';
import 'domain/usecases/rename_account.dart';
import 'presentation/bloc/account/account_bloc.dart';
import 'presentation/bloc/session/session_cubit.dart';
import 'presentation/bloc/theme/theme_cubit.dart';
import 'presentation/responsive/responsive_layout.dart';

class MultiWhatsAppWebApp extends StatelessWidget {
  const MultiWhatsAppWebApp({super.key, required this.formFactor});

  /// Determined once at startup in main.dart via `Platform.isX`
  /// (desktop OSes vs Android/iOS) per PRD §6.1 vs §6.2. The
  /// [ResponsiveLayout] widget additionally re-derives this from window
  /// width for dev-time previewing, but session-lifecycle rules (§27)
  /// key off this authoritative value, not window size.
  final FormFactor formFactor;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ThemeCubit()),
        BlocProvider(
          create: (_) => AccountBloc(
            watchAccounts: getIt<WatchAccounts>(),
            addAccount: getIt<AddAccount>(),
            renameAccount: getIt<RenameAccount>(),
            deleteAccount: getIt<DeleteAccount>(),
            logoutAccount: getIt<LogoutAccount>(),
          )..add(const AccountsSubscriptionRequested()),
        ),
        BlocProvider(
          create: (_) => SessionCubit(
            webViewAdapter: getIt<WebViewAdapter>(),
            accountRepository: getIt<AccountRepository>(),
            formFactor: formFactor,
          ),
        ),
      ],
      child: BlocBuilder<ThemeCubit, AppThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: switch (themeMode) {
              AppThemeMode.light => ThemeMode.light,
              AppThemeMode.dark => ThemeMode.dark,
              AppThemeMode.system => ThemeMode.system,
            },
            home: const ResponsiveLayout(),
          );
        },
      ),
    );
  }
}
