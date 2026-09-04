import 'package:get_it/get_it.dart';

import '../../data/datasources/local/account_local_datasource.dart';
import '../../data/datasources/local/account_lock_local_datasource.dart';
import '../../data/datasources/remote/update_remote_datasource.dart';
import '../../data/datasources/webview/webview_adapter_factory.dart';
import '../../data/repositories/account_repository_impl.dart';
import '../../data/repositories/update_repository_impl.dart';
import '../../domain/repositories/account_repository.dart';
import '../../domain/repositories/update_repository.dart';
import '../../domain/repositories/webview_adapter.dart';
import '../../domain/usecases/add_account.dart';
import '../../domain/usecases/check_for_update.dart';
import '../../domain/usecases/delete_account.dart';
import '../../domain/usecases/get_accounts.dart';
import '../../domain/usecases/logout_account.dart';
import '../../domain/usecases/observe_connection_status.dart';
import '../../domain/usecases/rename_account.dart';
import '../../domain/usecases/switch_account.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  final localDataSource = await AccountLocalDataSource.open();
  getIt.registerSingleton<AccountLocalDataSource>(localDataSource);

  getIt.registerSingleton<AccountLockLocalDatasource>(
    AccountLockLocalDatasource(),
  );

  getIt.registerSingleton<WebViewAdapter>(WebViewAdapterFactory.create());

  getIt.registerSingleton<UpdateRemoteDatasource>(UpdateRemoteDatasource());
  getIt.registerSingleton<UpdateRepository>(
    UpdateRepositoryImpl(getIt<UpdateRemoteDatasource>()),
  );
  getIt.registerFactory(() => CheckForUpdate(getIt<UpdateRepository>()));

  getIt.registerSingleton<AccountRepository>(
    AccountRepositoryImpl(getIt<AccountLocalDataSource>()),
  );

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
