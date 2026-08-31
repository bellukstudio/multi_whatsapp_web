// import 'dart:async';
//
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart' show Color;
// import 'package:webview_flutter/webview_flutter.dart';
//
// import '../../../../core/constants/app_constants.dart';
// import '../../../../domain/repositories/webview_adapter.dart';
//
// class MobileWebViewSessionHandle implements WebViewSessionHandle {
//   MobileWebViewSessionHandle({
//     required this.accountId,
//     bool desktopModeEnabled = false,
//   }) : desktopModeEnabled = ValueNotifier<bool>(desktopModeEnabled) {
//     controller = WebViewController()
//       ..setJavaScriptMode(JavaScriptMode.unrestricted)
//       ..setBackgroundColor(const Color(0x00000000))
//       ..setNavigationDelegate(
//         NavigationDelegate(onPageStarted: (_) => unawaited(_onPageStarted())),
//       );
//   }
//
//   @override
//   final String accountId;
//
//   late final WebViewController controller;
//
//   static const String desktopUserAgent =
//       'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
//       '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
//
//   static const String _desktopUAOverrideScript = '''
// (function() {
//   try {
//     Object.defineProperty(navigator, 'userAgentData', {
//       get: function() {
//         return {
//           brands: [
//             {brand: 'Not.A.Brand', version: '8'},
//             {brand: 'Chromium', version: '124'},
//             {brand: 'Google Chrome', version: '124'}
//           ],
//           mobile: false,
//           platform: 'Windows'
//         };
//       },
//       configurable: true
//     });
//   } catch (e) {}
// })();
// ''';
//
//   bool _pendingNavigate = false;
//
//   final ValueNotifier<bool> desktopModeEnabled;
//
//   final _statusController =
//       StreamController<AccountConnectionStatus>.broadcast();
//
//   final ValueNotifier<bool> shouldBeMounted = ValueNotifier<bool>(true);
//
//   @override
//   Stream<AccountConnectionStatus> get statusStream => _statusController.stream;
//
//   Future<void> _onPageStarted() async {
//     await _applyDesktopModeIfNeeded();
//   }
//
//   Future<void> setDesktopMode(bool enabled) async {
//     if (desktopModeEnabled.value == enabled) return;
//     desktopModeEnabled.value = enabled;
//     await _applyDesktopModeIfNeeded();
//     await _purgeServiceWorkerAndCaches();
//
//     await controller.loadRequest(Uri.parse(AppConstants.whatsappWebUrl));
//   }
//
//   Future<void> _purgeServiceWorkerAndCaches() async {
//     try {
//       await controller.runJavaScript('''
//       (async function() {
//         try {
//           const regs = await navigator.serviceWorker.getRegistrations();
//           for (const r of regs) { await r.unregister(); }
//         } catch (e) {}
//         try {
//           const keys = await caches.keys();
//           for (const k of keys) { await caches.delete(k); }
//         } catch (e) {}
//       })();
//     ''');
//     } catch (_) {}
//
//     try {
//       await controller.clearCache();
//     } catch (_) {}
//   }
//
//   Future<void> _applyDesktopModeIfNeeded() async {
//     await controller.setUserAgent(
//       desktopModeEnabled.value ? desktopUserAgent : null,
//     );
//     if (desktopModeEnabled.value) {
//       try {
//         await controller.runJavaScript(_desktopUAOverrideScript);
//       } catch (_) {}
//     }
//   }
//
//   @override
//   Future<void> navigateToWhatsAppWeb() async {
//     _statusController.add(AccountConnectionStatus.connecting);
//     await _load();
//   }
//
//   Future<void> _load() async {
//     await controller.loadRequest(Uri.parse(AppConstants.whatsappWebUrl));
//   }
//
//   @override
//   Future<void> reload() async {
//     await controller.reload();
//   }
//
//   @override
//   Future<void> pauseRendering() async {
//     await controller.runJavaScript(_visibilityScript(hidden: true));
//   }
//
//   @override
//   Future<void> resumeRendering() async {
//     await controller.runJavaScript(_visibilityScript(hidden: false));
//   }
//
//   String _visibilityScript({required bool hidden}) =>
//       '''
//     Object.defineProperty(document, 'hidden', {value: $hidden, configurable: true});
//     document.dispatchEvent(new Event('visibilitychange'));
//   ''';
//
//   @override
//   Future<void> unloadFromMemory() async {
//     shouldBeMounted.value = false;
//   }
//
//   @override
//   Future<int?> approximateMemoryBytes() async {
//     return null;
//   }
//
//   @override
//   Future<void> clearSessionData() async {
//     await WebViewCookieManager().clearCookies();
//     await controller.clearCache();
//   }
//
//   @override
//   Future<void> dispose() async {
//     await unloadFromMemory();
//     shouldBeMounted.dispose();
//     desktopModeEnabled.dispose();
//     await _statusController.close();
//   }
// }
