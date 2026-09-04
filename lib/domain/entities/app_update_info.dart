import 'package:equatable/equatable.dart';

class AppUpdateInfo extends Equatable {
  const AppUpdateInfo({
    required this.latestVersion,
    this.minSupportedVersion,
    this.releaseNotes,
    this.updateUrl,
    this.platformUpdateUrls = const {},
  });

  final String latestVersion;

  final String? minSupportedVersion;

  final String? releaseNotes;

  final String? updateUrl;

  final Map<String, String> platformUpdateUrls;

  String? urlFor(String platformKey) =>
      platformUpdateUrls[platformKey] ?? updateUrl;

  @override
  List<Object?> get props => [
    latestVersion,
    minSupportedVersion,
    releaseNotes,
    updateUrl,
    platformUpdateUrls,
  ];
}
