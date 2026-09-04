import '../../core/utils/semver.dart';
import '../entities/app_update_info.dart';
import '../repositories/update_repository.dart';

enum UpdateUrgency {
  /// Already on the latest version (or no update info published).
  none,

  /// A newer version exists, but the installed one is still usable.
  optional,

  /// The installed version is below `minSupportedVersion` — the
  /// reminder must block the user until they update.
  mandatory,
}

class UpdateCheckResult {
  const UpdateCheckResult({required this.urgency, this.info});

  final UpdateUrgency urgency;
  final AppUpdateInfo? info;
}

/// Compares [currentVersion] (from `package_info_plus`) against the
/// remotely published [AppUpdateInfo] and decides whether — and how
/// urgently — the user should be reminded to update.
class CheckForUpdate {
  const CheckForUpdate(this._repository);

  final UpdateRepository _repository;

  Future<UpdateCheckResult> call(String currentVersion) async {
    final info = await _repository.fetchLatestUpdateInfo();
    if (info == null) {
      return const UpdateCheckResult(urgency: UpdateUrgency.none);
    }

    final belowMinSupported =
        info.minSupportedVersion != null &&
        compareVersions(currentVersion, info.minSupportedVersion!) < 0;
    if (belowMinSupported) {
      return UpdateCheckResult(urgency: UpdateUrgency.mandatory, info: info);
    }

    final behindLatest = compareVersions(currentVersion, info.latestVersion) < 0;
    if (behindLatest) {
      return UpdateCheckResult(urgency: UpdateUrgency.optional, info: info);
    }

    return const UpdateCheckResult(urgency: UpdateUrgency.none);
  }
}
