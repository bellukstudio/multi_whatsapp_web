import '../../domain/entities/app_update_info.dart';
import '../../domain/repositories/update_repository.dart';
import '../datasources/remote/update_remote_datasource.dart';

class UpdateRepositoryImpl implements UpdateRepository {
  const UpdateRepositoryImpl(this._remote);

  final UpdateRemoteDatasource _remote;

  @override
  Future<AppUpdateInfo?> fetchLatestUpdateInfo() async {
    try {
      return await _remote.fetch();
    } catch (e, st) {
      // ignore: avoid_print
      print('fetchLatestUpdateInfo failed: $e\n$st');
      return null;
    }
  }
}
