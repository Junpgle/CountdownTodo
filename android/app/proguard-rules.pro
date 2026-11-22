# Flutter core & plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Keep annotated symbols & JNI / platform callbacks
-keepattributes *Annotation*
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# App receivers, widgets, and WorkManager background workers
-keep class com.math_quiz.junpgle.com.math_quiz_app.** { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class * extends android.appwidget.AppWidgetProvider { *; }
-keep class * extends android.content.BroadcastReceiver { *; }
