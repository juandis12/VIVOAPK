# Reglas de Ofuscación para My Auto Guide (VivoTV)
# Estas reglas previenen que R8 elimine clases críticas necesarias para Flutter y los plugins.

# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Supabase & Http
-keep class com.supabase.** { *; }
-keep class okhttp3.** { *; }
-keepnames class com.supabase.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }

# WebView
-keep class android.webkit.** { *; }

# Google Play Core (Fix R8 Missing Classes)
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.gms.internal.**

# Preservar anotaciones
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
