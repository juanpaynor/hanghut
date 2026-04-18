# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Supabase / OkHttp / Gson
-keep class io.github.jan.supabase.** { *; }
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Kotlin serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keep class kotlinx.serialization.** { *; }
-keepclassmembers class * {
    @kotlinx.serialization.SerialName <fields>;
}

# Geolocator / WorkManager
-keep class com.baseflow.geolocator.** { *; }
-keep class androidx.work.** { *; }

# Keep all model classes (JSON parsing)
-keep class com.hanghut.hanghut.** { *; }
-keepclassmembers class ** {
    public <init>(...);
}
