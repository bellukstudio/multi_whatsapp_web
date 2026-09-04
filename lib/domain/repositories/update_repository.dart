import '../entities/app_update_info.dart';

abstract class UpdateRepository {
  /// Fetches the currently published update info, or `null` if it
  /// hasn't been configured in Firestore yet, or couldn't be reached
  /// (offline, etc.) — callers should treat `null` as "nothing to
  /// report" rather than as an error.
  Future<AppUpdateInfo?> fetchLatestUpdateInfo();
}
