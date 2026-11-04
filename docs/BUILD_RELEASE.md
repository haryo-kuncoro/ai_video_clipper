# Build release: agar semua fitur (terjemahan, STT, FFmpeg) jalan di APK

Gejala: `flutter run` normal, tetapi APK hasil `flutter build apk` gagal unduh
model terjemahan ("pastikan Google Play Services aktif"). Penyebab umum: R8 memangkas
kelas ML Kit/JNI, dan/atau izin jaringan hanya ada di manifest debug.

## 1. Izin (android/app/src/main/AndroidManifest.xml, di luar <application>)
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```
(ML Kit memeriksa status jaringan sebelum mengunduh model.)

## 2. Aturan R8
Salin `native/android/proguard-rules.pro` ke `android/app/proguard-rules.pro`, lalu di
`android/app/build.gradle(.kts)` bagian `buildTypes { release { ... } }` tambahkan:

Kotlin DSL (.kts):
```kotlin
release {
    isMinifyEnabled = true
    isShrinkResources = true
    proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
}
```
Groovy:
```groovy
release {
    minifyEnabled true
    shrinkResources true
    proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
}
```
Uji cepat tanpa aturan: `flutter build apk --release --no-shrink`. Bila itu berhasil,
penyebabnya memang R8.

## 3. Bila masih gagal: baca lognya
```
adb logcat -c
adb logcat | findstr /i "mlkit translate ModelDownload AndroidRuntime flutter"
```
lalu tekan Unduh di aplikasi dan kirim barisnya.
