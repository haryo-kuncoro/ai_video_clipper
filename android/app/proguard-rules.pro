# Aturan R8 untuk build release AI CLIPPER.
# Tanpa ini, R8 memangkas kelas yang dipakai lewat refleksi/JNI sehingga fitur
# berjalan di `flutter run` (debug) tetapi gagal di APK release.

# ML Kit (terjemahan on-device)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_translate.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.odml.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.odml.**

# FFmpegKit (JNI)
-keep class com.arthenica.** { *; }
-dontwarn com.arthenica.**

# sherpa-onnx (JNI)
-keep class com.k2fsa.sherpa.onnx.** { *; }
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# Jembatan native aplikasi
-keep class com.haryo.ai_video_clipper.** { *; }
