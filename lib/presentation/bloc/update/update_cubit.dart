import 'dart:io' show Platform;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../domain/entities/app_update_info.dart';
import '../../../domain/usecases/check_for_update.dart';

part 'update_state.dart';

class UpdateCubit extends Cubit<UpdateState> {
  UpdateCubit(this._checkForUpdate, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage(),
      super(const UpdateState());

  final CheckForUpdate _checkForUpdate;
  final FlutterSecureStorage _storage;

  static const _skippedVersionKey = 'update_skipped_version';

  String get _platformKey {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'other';
  }

  Future<void> checkForUpdate() async {
    emit(state.copyWith(status: UpdateStatus.checking));
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final result = await _checkForUpdate(packageInfo.version);

      if (result.urgency == UpdateUrgency.none || result.info == null) {
        emit(
          state.copyWith(
            status: UpdateStatus.upToDate,
            info: null,
            currentVersion: packageInfo.version,
          ),
        );
        return;
      }

      if (result.urgency == UpdateUrgency.mandatory) {
        emit(
          state.copyWith(
            status: UpdateStatus.required,
            info: result.info,
            currentVersion: packageInfo.version,
          ),
        );
        return;
      }

      final skippedVersion = await _storage.read(key: _skippedVersionKey);
      if (skippedVersion == result.info!.latestVersion) {
        emit(
          state.copyWith(
            status: UpdateStatus.upToDate,
            info: null,
            currentVersion: packageInfo.version,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          status: UpdateStatus.available,
          info: result.info,
          currentVersion: packageInfo.version,
        ),
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('UpdateCubit.checkForUpdate failed: $e\n$st');
      emit(state.copyWith(status: UpdateStatus.upToDate, info: null));
    }
  }

  Future<void> skipCurrentVersion() async {
    final info = state.info;
    if (info == null || state.status != UpdateStatus.available) return;
    await _storage.write(key: _skippedVersionKey, value: info.latestVersion);
    emit(state.copyWith(status: UpdateStatus.upToDate, info: null));
  }

  String? updateUrlForThisPlatform() => state.info?.urlFor(_platformKey);
}
