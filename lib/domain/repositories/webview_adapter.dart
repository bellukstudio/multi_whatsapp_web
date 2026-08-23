import '../../core/constants/app_constants.dart';

/// Result of attempting to provision an isolated, persistent browser
/// profile for one account. This is the artifact the PRD §24 "PoC
/// pass/fail" decision is based on:
///
///   "jika WebView engine yang dipilih di platform manapun tidak
///    menyediakan isolasi yang benar, PoC untuk platform tersebut
///    dianggap gagal dan tidak boleh lanjut ke UI/architecture penuh."
class IsolationProbeResult {
  const IsolationProbeResult({
    required this.isSupported,
    required this.engine,
    required this.isNativeIsolation,
    this.reason,
  });

  final bool isSupported;
  final WebViewEngineKind engine;

  /// true  -> native persistent isolated data store (e.g.
  ///          WKWebsiteDataStore(forIdentifier:), setDataDirectorySuffix)
  /// false -> would require a manual cookie-management fallback, which
  ///          PRD §24 flags as "lebih kompleks, lebih rawan bug
  ///          cookie-bleeding antar akun" and NOT recommended.
  final bool isNativeIsolation;

  final String? reason;
}

/// One live (or suspended) WebView instance bound to a single account's
/// isolated profile. Desktop implementations may keep several of these
/// warm at once (§26 desktop); the mobile implementation must guarantee
/// at most [AppConstants.maxActiveWebViewsOnMobile] are truly active in
/// memory at any time (§27 — mandatory since MVP on mobile).
abstract class WebViewSessionHandle {
  String get accountId;

  Stream<AccountConnectionStatus> get statusStream;

  Future<void> navigateToWhatsAppWeb();

  Future<void> reload();

  /// Cheaper-than-unload throttle for sessions that are kept warm but not
  /// currently visible (desktop only, PRD §26 "10 akun: resource
  /// dimonitor"). Injects a JS visibility-change signal so WhatsApp Web's
  /// own background-tab throttling kicks in (reduced timers/re-render),
  /// WITHOUT tearing down the WebView the way [unloadFromMemory] does.
  /// No-op on mobile, where inactive accounts go straight to
  /// [unloadFromMemory] instead (§27 — full unload is mandatory there).
  Future<void> pauseRendering();

  /// Reverses [pauseRendering] when a paused-but-still-warm session
  /// becomes visible again.
  Future<void> resumeRendering();

  /// Fully tears down the WebView + releases memory, WITHOUT deleting the
  /// persisted profile on disk (used when suspending on mobile, PRD §27,
  /// and for LRU eviction of warm desktop sessions beyond
  /// [AppConstants.maxRecommendedDesktopSessions]).
  Future<void> unloadFromMemory();

  /// Best-effort resident memory footprint of this session in bytes, used
  /// purely for the §26 instrumentation the PRD asks for ("resource
  /// dimonitor" desktop, "battery impact harus diuji" mobile). Returns
  /// null where the platform doesn't expose a reliable per-WebView figure
  /// — callers should fall back to whole-process RSS in that case (see
  /// [MemoryProfiler]).
  Future<int?> approximateMemoryBytes();

  /// Deletes persisted cookies/local storage/IndexedDB for this profile
  /// (used by "Logout account", PRD §12) but keeps the account entry.
  Future<void> clearSessionData();

  Future<void> dispose();
}

/// Platform WebView Adapter (PRD §10 diagram, §24 table).
///
/// One concrete implementation per platform lives under
/// `data/datasources/webview/{desktop,mobile}/`. The presentation and
/// domain layers only ever talk to this interface — they never import
/// webview_windows / flutter_inappwebview directly.
abstract class WebViewAdapter {
  WebViewEngineKind get engineKind;

  /// PRD §24 Phase 1 PoC gate — must be run and confirmed `isSupported &&
  /// isNativeIsolation` before Phase 2 (Core Account Management) proceeds
  /// for this platform.
  Future<IsolationProbeResult> probeIsolationSupport();

  /// Creates (or resumes, if [sessionPath] already has persisted data) an
  /// isolated WebView profile scoped to [sessionPath]. `accountId` is used
  /// as the data-directory suffix / data-store identifier so two accounts
  /// can never share cookies/localStorage/IndexedDB (PRD §25).
  Future<WebViewSessionHandle> createOrResumeSession({
    required String accountId,
    required String sessionPath,
  });

  /// PRD §11: mobile OS may fully kill the WebView process while
  /// backgrounded. This tells the adapter to reload from persisted
  /// storage rather than assume in-memory continuity.
  Future<WebViewSessionHandle> reloadFromPersistedStorage({
    required String accountId,
    required String sessionPath,
  });
}
