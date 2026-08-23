import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:multi_whatsapp_web/core/constants/app_constants.dart';
import 'package:multi_whatsapp_web/domain/repositories/account_repository.dart';
import 'package:multi_whatsapp_web/domain/repositories/webview_adapter.dart';
import 'package:multi_whatsapp_web/domain/usecases/delete_account.dart';
import 'package:multi_whatsapp_web/domain/usecases/logout_account.dart';
import 'package:multi_whatsapp_web/presentation/bloc/session/session_cubit.dart';

class MockAccountRepository extends Mock implements AccountRepository {}

class MockWebViewAdapter extends Mock implements WebViewAdapter {}

class MockWebViewSessionHandle extends Mock implements WebViewSessionHandle {}

void main() {
  group('logout and delete actions', () {
    late MockAccountRepository repository;
    late MockWebViewAdapter adapter;
    late MockWebViewSessionHandle handle;

    setUp(() {
      repository = MockAccountRepository();
      adapter = MockWebViewAdapter();
      handle = MockWebViewSessionHandle();
    });

    test('LogoutAccount clears the session and marks the account logged out', () async {
      when(() => adapter.createOrResumeSession(
            accountId: 'acct-1',
            sessionPath: '/tmp/session-acct-1',
          )).thenAnswer((_) async => handle);
      when(() => handle.clearSessionData()).thenAnswer((_) async {});
      when(() => repository.logoutAccount('acct-1')).thenAnswer((_) async {});

      final usecase = LogoutAccount(repository, adapter);

      await usecase(id: 'acct-1', sessionPath: '/tmp/session-acct-1');

      verify(() => adapter.createOrResumeSession(
            accountId: 'acct-1',
            sessionPath: '/tmp/session-acct-1',
          )).called(1);
      verify(() => handle.clearSessionData()).called(1);
      verify(() => repository.logoutAccount('acct-1')).called(1);
    });

    test('DeleteAccount removes the account from repository', () async {
      when(() => repository.deleteAccount('acct-2')).thenAnswer((_) async {});

      final usecase = DeleteAccount(repository);

      await usecase('acct-2');

      verify(() => repository.deleteAccount('acct-2')).called(1);
    });

    test('SessionCubit releases the active handle before logout clears its data', () async {
      final sessionCubit = SessionCubit(
        webViewAdapter: adapter,
        accountRepository: repository,
        formFactor: FormFactor.mobile,
      );

      when(() => handle.unloadFromMemory()).thenAnswer((_) async {});
      when(() => handle.dispose()).thenAnswer((_) async {});
      sessionCubit.emit(sessionCubit.state.copyWith(
        activeAccountId: 'acct-3',
        status: ActiveSessionStatus.ready,
        handle: handle,
      ));

      await sessionCubit.releaseAccount('acct-3');

      verify(() => handle.unloadFromMemory()).called(1);
      verify(() => handle.dispose()).called(1);
      await sessionCubit.close();
    });
  });
}
