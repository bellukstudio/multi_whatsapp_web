part of 'session_cubit.dart';

enum ActiveSessionStatus { none, loading, ready, reconnecting, error }

class SessionState extends Equatable {
  const SessionState({
    this.activeAccountId,
    this.status = ActiveSessionStatus.none,
    this.handle,
    this.errorMessage,
  });

  final String? activeAccountId;
  final ActiveSessionStatus status;

  /// The live WebView handle for [activeAccountId], if any. Only ever
  /// non-null for the currently active account — PRD §27 mandates at
  /// most one truly-active WebView on mobile at any time.
  final WebViewSessionHandle? handle;

  /// Set when [status] is [ActiveSessionStatus.error] — e.g. a platform
  /// adapter refusing to create a session because it hasn't passed its
  /// PRD §24 isolation PoC yet. Shown to the user by [WebViewContainer]
  /// instead of letting the exception crash the app.
  final String? errorMessage;

  SessionState copyWith({
    String? activeAccountId,
    ActiveSessionStatus? status,
    WebViewSessionHandle? handle,
    String? errorMessage,
    bool clearHandle = false,
    bool clearError = false,
  }) {
    return SessionState(
      activeAccountId: activeAccountId ?? this.activeAccountId,
      status: status ?? this.status,
      handle: clearHandle ? null : (handle ?? this.handle),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [activeAccountId, status, handle, errorMessage];
}
