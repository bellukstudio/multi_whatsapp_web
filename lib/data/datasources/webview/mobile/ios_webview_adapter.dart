// import 'package:multi_whatsapp_web/core/constants/app_constants.dart';
//
// import '../../../../domain/repositories/webview_adapter.dart';
// import 'mobile_webview_session_handle.dart';
//
// class IOSWebViewAdapter implements WebViewAdapter {
//   @override
//   WebViewEngineKind get engineKind => WebViewEngineKind.inAppWebViewIOS;
//
//   @override
//   Future<IsolationProbeResult> probeIsolationSupport() async {
//     return const IsolationProbeResult(
//       isSupported: false,
//       engine: WebViewEngineKind.inAppWebViewIOS,
//       isNativeIsolation: false,
//       reason:
//           'webview_flutter_wkwebview (the package now used on iOS, '
//           'after moving off flutter_inappwebview to resolve a '
//           'Windows-only DispatcherQueueController conflict) has no '
//           'public API for a per-instance WKWebsiteDataStore identifier. '
//           'Accounts currently share one cookie/localStorage store on '
//           'iOS. See mobile_webview_session_handle.dart doc comment for '
//           'how to restore genuine isolation if this is required before '
//           'shipping.',
//     );
//   }
//
//   @override
//   Future<WebViewSessionHandle> createOrResumeSession({
//     required String accountId,
//     required String sessionPath,
//   }) async {
//     return MobileWebViewSessionHandle(accountId: accountId);
//   }
//
//   @override
//   Future<WebViewSessionHandle> reloadFromPersistedStorage({
//     required String accountId,
//     required String sessionPath,
//   }) {
//     return createOrResumeSession(
//       accountId: accountId,
//       sessionPath: sessionPath,
//     );
//   }
// }
