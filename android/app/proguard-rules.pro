# Flutter ProGuard / R8 Rules for MeenMart Store

# Flutter Wrapper & Plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

# ─── FIREBASE / FCM (CRITICAL - Release Build) ────────────────────────────────
# Keep all Firebase classes to prevent R8 from stripping background handlers
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.iid.** { *; }
-keepclasseswithmembers class * {
    @com.google.firebase.messaging.* <methods>;
}
# Keep the FCM background message handler entry point
-keep @com.google.firebase.messaging.FirebaseMessagingService public class *
-keepclassmembers class * extends com.google.firebase.messaging.FirebaseMessagingService {
    public void onMessageReceived(com.google.firebase.messaging.RemoteMessage);
    public void onNewToken(java.lang.String);
    public void onDeletedMessages();
}
# Ensure Dart VM entry point pragma survives R8
-keepclassmembers class ** {
    @dalvik.annotation.EnclosingMethod *;
}
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Google Play Core & Split Install
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# ─── SUPABASE & NETWORKING ────────────────────────────────────────────────────
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses
-keep class com.supabase.** { *; }
-keep class io.github.jan.supabase.** { *; }
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**
# OkHttp (used by Supabase/Ktor internally)
-dontwarn okhttp3.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# ─── FLUTTER PLUGINS ──────────────────────────────────────────────────────────
# Audioplayers
-keep class xyz.luan.audioplayers.** { *; }

# Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Image Picker & Cropper
-keep class io.flutter.plugins.imagepicker.** { *; }

# Geolocator / GPS Punch-In
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**
-keep class com.google.android.gms.location.** { *; }
-dontwarn com.google.android.gms.location.**

# ─── JAVA DESUGARING ──────────────────────────────────────────────────────────
-dontwarn java.lang.invoke.**
-dontwarn org.bouncycastle.**
-dontwarn sun.misc.**
