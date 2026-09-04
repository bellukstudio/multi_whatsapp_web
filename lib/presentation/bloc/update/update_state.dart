part of 'update_cubit.dart';

enum UpdateStatus { initial, checking, upToDate, available, required }

class UpdateState extends Equatable {
  const UpdateState({
    this.status = UpdateStatus.initial,
    this.info,
    this.currentVersion,
  });

  final UpdateStatus status;
  final AppUpdateInfo? info;
  final String? currentVersion;

  UpdateState copyWith({
    UpdateStatus? status,
    AppUpdateInfo? info,
    String? currentVersion,
  }) {
    return UpdateState(
      status: status ?? this.status,
      info: info,
      currentVersion: currentVersion ?? this.currentVersion,
    );
  }

  @override
  List<Object?> get props => [status, info, currentVersion];
}
