# =============================================================================
# ProGuard / R8 rules — Multi WhatsApp Web (Android release build)
# =============================================================================
# NOTE: R8/ProGuard only processes the Java/Kotlin side of the app (the
# Flutter engine embedding + Android plugin glue code, plus any native
# Android code you wrote yourself under android/app/src/main/...). Your
# Dart code (blocs, cubits, Isar models, the account-lock feature, etc.)
# is AOT-compiled straight to native machine code and is NOT touched by
# these rules at all — so nothing here needs to reference Dart classes.
# =============================================================================


# -----------------------------------------------------------------------------
# Flutter engine & plugin embedding
# -----------------------------------------------------------------------------
# Modern Flutter Gradle plugin already ships most of this automatically, but
# keeping it explicit is harmless and protects against older AGP/Flutter
# combinations that don't wire it in for you.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**


# -----------------------------------------------------------------------------
# flutter_secure_storage (^9.2.4)
# -----------------------------------------------------------------------------
# Backs onto AndroidX Security's EncryptedSharedPreferences, which pulls in
# Google Tink for the actual AES/GCM crypto. Tink and androidx.security use
# reflection to pick crypto providers at runtime, so they need to survive
# shrinking/obfuscation. This is also exactly what our new per-account
# password-lock feature relies on (account_lock_local_datasource.dart), so
# don't skip this section.
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**
-dontwarn com.google.errorprone.annotations.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**


# -----------------------------------------------------------------------------
# isar_community / isar_community_flutter_libs (^3.3.2)
# -----------------------------------------------------------------------------
# Isar talks to its native (.so) engine straight from Dart via dart:ffi, not
# through Java reflection, so there is normally nothing to keep here. Some
# versions ship a tiny Kotlin FlutterPlugin shim purely to trigger loading
# the native library on registration — keep that if R8 complains about a
# missing "isar" class during a release build.
-dontwarn dev.isar.**
# -keep class dev.isar.** { *; }   # uncomment if R8 reports a missing Isar class


# -----------------------------------------------------------------------------
# path_provider, device_info_plus
# -----------------------------------------------------------------------------
# Standard Flutter plugins using explicit method-channel registration (no
# reflection); nothing special required, but the -keep,allowobfuscation
# below is a cheap safety net for any auto-generated plugin registrant.
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class dev.fluttercommunity.plus.device_info.** { *; }


# -----------------------------------------------------------------------------
# General Flutter plugin registrant safety net
# -----------------------------------------------------------------------------
# Keeps any class that implements Flutter's plugin interfaces, regardless of
# package, so a plugin's registration code never gets stripped or renamed.
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
-keep class * implements io.flutter.plugin.platform.PlatformViewFactory { *; }
-keep class * implements io.flutter.plugin.platform.PlatformView { *; }


# -----------------------------------------------------------------------------
# Your own native Android WebView integration
# -----------------------------------------------------------------------------
# android_webview_adapter.dart / slot_embed_webview_session_handle.dart talk
# to native Android code over a MethodChannel + PlatformView (the per-account
# embedded WebView isn't a third-party plugin, so it lives in your own
# android/app/src/main/kotlin (or java) source set). If that native side uses
# any reflection-based instantiation (Class.forName, etc.) — which is
# unusual for hand-written MethodChannel/PlatformView code — keep it below.
# Replace the package with your actual applicationId.
# -keep class com.yourcompany.multiwhatsappweb.** { *; }


# -----------------------------------------------------------------------------
# Kotlin / AndroidX noise suppression
# -----------------------------------------------------------------------------
-dontwarn kotlin.**
-dontwarn kotlinx.**
-dontwarn javax.annotation.**
-keep class kotlin.Metadata { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod, SourceFile, LineNumberTable


# -----------------------------------------------------------------------------
# Parcelable / enum safety (defensive — cheap, avoids obscure crashes)
# -----------------------------------------------------------------------------
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}