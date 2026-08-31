part of 'session_cubit.dart';

enum ActiveSessionStatus { none, loading, ready, reconnecting, error }

class SessionState extends Equatable {
  const SessionState({
    this.activeAccountId,
    this.status = ActiveSessionStatus.none,
    this.handle,
    this.errorMessage,
    this.errorNeedsAppRestart = false,
  });

  final String? activeAccountId;
  final ActiveSessionStatus status;

  final WebViewSessionHandle? handle;

  final String? errorMessage;

  final bool errorNeedsAppRestart;

  SessionState copyWith({
    String? activeAccountId,
    ActiveSessionStatus? status,
    WebViewSessionHandle? handle,
    String? errorMessage,
    bool errorNeedsAppRestart = false,
    bool clearHandle = false,
    bool clearError = false,
  }) {
    return SessionState(
      activeAccountId: activeAccountId ?? this.activeAccountId,
      status: status ?? this.status,
      handle: clearHandle ? null : (handle ?? this.handle),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorNeedsAppRestart: clearError
          ? false
          : (errorNeedsAppRestart || this.errorNeedsAppRestart),
    );
  }

  @override
  List<Object?> get props => [
    activeAccountId,
    status,
    handle,
    errorMessage,
    errorNeedsAppRestart,
  ];
}
