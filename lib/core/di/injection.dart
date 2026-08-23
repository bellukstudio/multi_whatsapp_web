import 'package:get_it/get_it.dart';

import '../../data/datasources/local/account_local_datasource.dart';
import '../../data/datasources/webview/webview_adapter_factory.dart';
import '../../data/repositories/account_repository_impl.dart';
import '../../domain/repositories/account_repository.dart';
import '../../domain/repositories/webview_adapter.dart';
import '../../domain/usecases/add_account.dart';
import '../../domain/usecases/delete_account.dart';
import '../../domain/usecases/get_accounts.dart';
import '../../domain/usecases/logout_account.dart';
import '../../domain/usecases/observe_connection_status.dart';
import '../../domain/usecases/rename_account.dart';
import '../../domain/usecases/switch_account.dart';

/// Manual composition root (kept simple/manual rather than full
/// `injectable` codegen for this scaffold, so it's readable without
/// running build_runner first). Swap for @injectable annotations later
/// if the team wants generated DI once the project is building for real.
final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  // --- Data sources -------------------------------------------------
  final localDataSource = await AccountLocalDataSource.open();
  getIt.registerSingleton<AccountLocalDataSource>(localDataSource);

  // PRD §10: the ONE runtime platform-branch, isolated in the factory.
  getIt.registerSingleton<WebViewAdapter>(WebViewAdapterFactory.create());

  // --- Repositories ---------------------------------------------------
  getIt.registerSingleton<AccountRepository>(
    AccountRepositoryImpl(getIt<AccountLocalDataSource>()),
  );

  // --- Use cases --------------------------------------------------------
  getIt.registerFactory(() => WatchAccounts(getIt<AccountRepository>()));
  getIt.registerFactory(() => AddAccount(getIt<AccountRepository>()));
  getIt.registerFactory(() => RenameAccount(getIt<AccountRepository>()));
  getIt.registerFactory(() => DeleteAccount(getIt<AccountRepository>()));
  getIt.registerFactory(
    () => LogoutAccount(getIt<AccountRepository>(), getIt<WebViewAdapter>()),
  );
  getIt.registerFactory(() => SwitchAccount(getIt<AccountRepository>()));
  getIt.registerFactory(
    () => ObserveAccountStatuses(getIt<AccountRepository>()),
  );
}
