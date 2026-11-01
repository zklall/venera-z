# Test entry points are called from a separate instrumentation APK. The source
# API itself uses exactly the same consumer rules as the shipping app.
-keep class com.github.veneraz.mihon.MihonRuntime { public *; }
# The separate AndroidX test runner shares these dependencies with its host.
-keep class androidx.** { *; }
