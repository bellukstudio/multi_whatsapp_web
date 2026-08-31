import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:multi_whatsapp_web/presentation/splash.dart';

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
import 'presentation/bloc/session/session_pool_manager.dart';
import 'presentation/bloc/theme/theme_cubit.dart';
import 'presentation/responsive/responsive_layout.dart';

/// FIX (native WebView bleeding through Flutter dialogs/pages): the
/// desktop native WebView surfaces (WebKitGTK on Linux, and similarly
/// webview_windows on Windows) are composited ABOVE the entire Flutter
/// `FlView` — a plain `Navigator.push`/`showDialog` never actually
/// covers them, because Flutter has no idea a separate native widget
/// exists on top of it at all. The previous fix for this
/// (`showOverlaySafely`, calling pauseRendering()/resumeRendering()
/// imperatively at each navigation call site) turned out to be too easy
/// to miss or get wrong — Settings and Add Account both slipped through
/// at different points.
///
/// This `RouteObserver` is the structural fix: any widget that mixes in
/// `RouteAware` and subscribes to it (see `_LinuxEngineSurfaceState` in
/// `webview_container.dart`) automatically gets `didPushNext()` /
/// `didPopNext()` callbacks whenever ANY route is pushed/popped on top
/// of its own route — no matter which screen does the navigating, and
/// with no risk of a call site forgetting to wrap itself. The native
/// view hides/shows itself; nothing else needs to remember to ask it to.
final RouteObserver<ModalRoute<void>> desktopWebViewRouteObserver =
    RouteObserver<ModalRoute<void>>();

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
            // Windows only ever keeps ONE WebviewController alive at a
            // time (see windows_webview_adapter.dart) — a second
            // concurrently-warm controller is what caused the
            // "Creating DispatcherQueueController failed" crash.
            // Capping the warm pool at 1 here makes SessionPoolManager
            // fully dispose the previous session before creating the
            // next one, instead of trying to keep several warm side by
            // side. Other desktop platforms keep the full §26 cap.
            poolManager: formFactor == FormFactor.desktop && Platform.isWindows
                ? SessionPoolManager(
                    webViewAdapter: getIt<WebViewAdapter>(),
                    maxWarmSessions: 1,
                  )
                : null,
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
            navigatorObservers: [desktopWebViewRouteObserver],
            home: Builder(
              builder: (innerContext) => SplashPage(
                appName: 'Multi WhatsApp Web',
                onFinished: () {
                  Navigator.of(innerContext).pushReplacement(
                    MaterialPageRoute(builder: (_) => const ResponsiveLayout()),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
