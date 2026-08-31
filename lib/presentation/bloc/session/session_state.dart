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

  /// The live WebView handle for [activeAccountId], if any. Only ever
  /// non-null for the currently active account — PRD §27 mandates at
  /// most one truly-active WebView on mobile at any time.
  final WebViewSessionHandle? handle;

  /// Set when [status] is [ActiveSessionStatus.error] — e.g. a platform
  /// adapter refusing to create a session because it hasn't passed its
  /// PRD §24 isolation PoC yet. Shown to the user by [WebViewContainer]
  /// instead of letting the exception crash the app.
  final String? errorMessage;

  /// True when [errorMessage] came from a
  /// `WebView2RuntimeMissingException.isDispatcherQueueConflict` — see
  /// `windows_webview_adapter.dart`. Retrying/waiting never fixes this;
  /// [WebViewContainer]'s error state uses this to show a "Restart
  /// Aplikasi" action ([AppRestarter]) instead of a generic retry hint.
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
      errorNeedsAppRestart:
          clearError ? false : (errorNeedsAppRestart || this.errorNeedsAppRestart),
    );
  }

  @override
  List<Object?> get props =>
      [activeAccountId, status, handle, errorMessage, errorNeedsAppRestart];
}