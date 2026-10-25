# Android installation and recovery compatibility

This is a source/configuration audit, **not** a claim that every device or OS version has been tested. The application ID is `com.photorecoveryrestore.app`, minSdk is 26, and the current build requests targetSdk at least 36. The Play release does not request all-files access. Android grants only the photo scope the user chooses.

| Android | API | Media permission and discovery path | Save / trash path | Runtime installation, scanning and restore |
|---|---:|---|---|---|
| 8.0 | 26 | Legacy read/write grants; MediaStore and accessible shared storage | Legacy MediaStore copy; no supported system-trash restore | Not device-tested |
| 8.1 | 27 | Same API 26 path | Same API 26 path | Not device-tested |
| 9 | 28 | Same API 26 path | Same API 26 path | Not device-tested |
| 10 | 29 | Legacy read grant; scoped MediaStore, optional legacy file visibility | MediaStore copy with `IS_PENDING`; no Android 11 trash request | Not device-tested |
| 11 | 30 | Legacy read grant; scoped MediaStore; release deep file traversal restricted | MediaStore copy; supported system-trash request | Not device-tested |
| 12 | 31 | Same scoped path as API 30 | Same API 30 path | Not device-tested |
| 12L | 32 | Same scoped path as API 30 | Same API 30 path | Not device-tested |
| 13 | 33 | `READ_MEDIA_IMAGES`; MediaStore | MediaStore copy and trash request | Not device-tested |
| 14 | 34 | Full images or user-selected limited photos; MediaStore | MediaStore copy and trash request within granted scope | Not device-tested |
| 15 | 35 | Same permission-scope split as API 34 | Same API 34 path | Not device-tested |
| 16 | 36 | Same permission-scope split as API 34 | Same API 34 path | Not device-tested |
| 17 | 37 | Current API 34+ permission branches; test against Android 17's all-app memory limits | Current API 34+ branches; target remains 36 | Not device-tested; Android 17 behavior review and runtime tests required |

The Kotlin calls to Android 10+ MediaStore metadata and `IS_PENDING`, Android 11+ trash requests, and Android 13/14+ permissions are SDK-guarded. The Flutter activity uses embedding v2. The app has no third-party runtime Flutter plugin dependency in `pubspec.yaml`; the Android library dependency is the Flutter engine. Source and tests cannot prove runtime behavior on every OEM device.

## Previous APK inspection (not a new build)

The user-supplied `C:\Users\AT\Documents\release\release\app-release.apk` was inspected read-only. It reports package `com.photorecoveryrestore.app`, version `1.0.0` (`versionCode=1`), minSdk 26, targetSdk 36, and `armeabi-v7a`, `arm64-v8a`, and `x86_64` native code. APK Signature Scheme v2 verification succeeds, and `zipalign -c -P 16 -v 4` reports success. This does **not** identify why a particular device displayed “App not installed”; the exact `adb install` failure is needed. This APK predates the current source changes.

The prior release intermediates contain `libapp.so` and `libflutter.so` for each listed ABI. Their ARM64 ELF `LOAD` segment alignment is `0x10000` (64 KiB), which exceeds 16 KiB. The inspected APK has 16 KiB ZIP alignment. These are artifact checks, not a 16 KiB device run. Recheck the actual newly built APK/AAB and every packaged `.so` after release; do not infer future artifacts from these intermediates.

## Signing and versions

`android/signing.properties` is absent in this workspace. Release builds no longer silently use the debug certificate: provide the **existing** upload/release key before building an installable release APK or Play AAB. The existing APK is signed by a non-debug certificate; its certificate must match any update to that installation. The source version remains `1.0.0+1`. Increase the version code for an update. Do not replace the existing key or automatically uninstall an installed copy; uninstalling removes app-private data.

## Windows device diagnosis (PowerShell or Android Studio terminal)

Set `adb` to your SDK's `platform-tools` executable, or use the full path on every line:

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb devices -l
& $adb shell getprop ro.build.version.release
& $adb shell getprop ro.build.version.sdk
& $adb shell getprop ro.product.cpu.abilist
& $adb shell getconf PAGE_SIZE
& $adb shell pm list packages com.photorecoveryrestore.app
& $adb shell dumpsys package com.photorecoveryrestore.app | Select-String 'versionCode|versionName|signatures'
& $adb install -r 'C:\path\to\your\signed\app-release.apk'
& $adb shell monkey -p com.photorecoveryrestore.app 1
& $adb logcat -d -v time | Select-String 'AndroidRuntime|FATAL EXCEPTION|com.photorecoveryrestore.app|Recovery inventory page=|Deep page=|Scan terminal state:'
```

`adb install -r` attempts an upgrade without uninstalling or permitting a downgrade. Save the complete installer output, not just the phone's “App not installed” popup. Run Recover Photos after launch, grant the requested photo scope, then capture the final log command. Logs may contain filenames or paths: review and redact personal information before sharing.

Common failures: `INSTALL_FAILED_NO_MATCHING_ABIS` means the APK lacks a supported CPU library; `INSTALL_FAILED_OLDER_SDK` means minSdk exceeds the phone API; `INSTALL_FAILED_UPDATE_INCOMPATIBLE` indicates a signature mismatch for an installed package; `INSTALL_FAILED_VERSION_DOWNGRADE` means the incoming version code is lower; `INSTALL_FAILED_MISSING_SPLIT` means an ABI/configuration split is absent; `INSTALL_FAILED_INVALID_APK` means the package is malformed or otherwise rejected; and `INSTALL_FAILED_INSUFFICIENT_STORAGE` means the install needs more free storage. A signature mismatch should be resolved with the original signing key and a suitable version code when possible. Before considering uninstall, back up app-private data and understand that uninstall removes it.

After building a new artifact locally, check its manifest, signatures, native libraries, ZIP alignment and AAB page-alignment declaration with Android SDK `aapt`, `apksigner`, `zipalign -c -P 16 -v 4`, and `bundletool dump config --bundle=<file.aab>`. For ELF alignment, inspect each `.so` `LOAD` segment using NDK `llvm-readelf -l`. Android's [16 KiB page-size guide](https://developer.android.com/guide/practices/page-sizes) describes the checks. Android's [Android 17 all-app changes](https://developer.android.com/about/versions/17/behavior-changes-all) include new app memory limits, so scan and large-gallery behavior still needs an API 37 device/emulator run.
