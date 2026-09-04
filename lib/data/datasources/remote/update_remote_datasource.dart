import 'package:firedart/firestore/firestore.dart';

import '../../../domain/entities/app_update_info.dart';


class UpdateRemoteDatasource {
  UpdateRemoteDatasource({
    this.collectionPath = 'app_config',
    this.documentId = 'update_info',
  });

  final String collectionPath;
  final String documentId;

  Future<AppUpdateInfo?> fetch() async {
    final document = await Firestore.instance
        .collection(collectionPath)
        .document(documentId)
        .get();

    final map = document.map;
    if (map.isEmpty) return null;

    final latestVersion = map['latestVersion'] as String?;
    if (latestVersion == null || latestVersion.isEmpty) return null;

    final platformUrls = <String, String>{};
    final rawPlatformUrls = map['platformUpdateUrls'];
    if (rawPlatformUrls is Map) {
      for (final entry in rawPlatformUrls.entries) {
        final key = entry.key?.toString();
        final value = entry.value?.toString();
        if (key != null && value != null && value.isNotEmpty) {
          platformUrls[key] = value;
        }
      }
    }

    return AppUpdateInfo(
      latestVersion: latestVersion,
      minSupportedVersion: map['minSupportedVersion'] as String?,
      releaseNotes: map['releaseNotes'] as String?,
      updateUrl: map['updateUrl'] as String?,
      platformUpdateUrls: platformUrls,
    );
  }
}
