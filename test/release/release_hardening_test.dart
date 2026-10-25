import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release configuration keeps ARM-only optimized AAB hardening', () {
    final buildFile = File('android/app/build.gradle.kts').readAsStringSync();

    expect(buildFile, contains('compileSdk = maxOf(flutter.compileSdkVersion, 36)'));
    expect(buildFile, contains('minSdk = 26'));
    // Flutter supplies release ABI filters; do not add an explicit NDK filter.
    expect(
      buildFile,
      isNot(matches(RegExp(r'ndk\s*\{[^}]*abiFilters', dotAll: true))),
    );
    expect(buildFile, isNot(contains('"x86"')));
    expect(buildFile, isNot(contains('"x86_64"')));
    expect(
      buildFile,
      matches(
        RegExp(
          r'bundle\s*\{\s*abi\s*\{\s*enableSplit\s*=\s*true\s*\}\s*density\s*\{\s*enableSplit\s*=\s*true\s*\}\s*\}',
          dotAll: true,
        ),
      ),
    );
    expect(buildFile, contains('targetSdk = maxOf(flutter.targetSdkVersion, 36)'));
    expect(buildFile, contains('namespace = "com.photorecoveryrestore.app"'));
    expect(
      buildFile,
      contains('applicationId = "com.photorecoveryrestore.app"'),
    );
    expect(buildFile, isNot(contains('com.example.photo_recovery_restore')));
    expect(buildFile, contains('isDebuggable = false'));
    expect(buildFile, contains('isMinifyEnabled = true'));
    expect(buildFile, contains('isShrinkResources = true'));
    expect(buildFile, isNot(contains('signingConfigs.getByName("debug")')));
  });

  test(
    'local APK ABI splits use Flutter instead of conflicting static filters',
    () {
      final buildFile = File('android/app/build.gradle.kts').readAsStringSync();
      final readme = File('README.md').readAsStringSync();

      expect(
        buildFile,
        isNot(matches(RegExp(r'ndk\s*\{[^}]*abiFilters', dotAll: true))),
      );
      expect(
        buildFile,
        isNot(matches(RegExp(r'splits\s*\{\s*abi\b', dotAll: true))),
      );
      expect(
        readme,
        contains(
          'flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64',
        ),
      );
    },
  );

  test('AGP 9 uses a Flutter-compatible Kotlin plugin and Gradle 9', () {
    final settings = File('android/settings.gradle.kts').readAsStringSync();
    final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
    final gradleProperties = File(
      'android/gradle.properties',
    ).readAsStringSync();
    final wrapper = File(
      'android/gradle/wrapper/gradle-wrapper.properties',
    ).readAsStringSync();

    expect(
      settings,
      contains('id("com.android.application") version "9.1.1" apply false'),
    );
    expect(
      settings,
      contains(
        'id("org.jetbrains.kotlin.android") version "2.4.0" apply false',
      ),
    );
    expect(appBuild, contains('id("org.jetbrains.kotlin.android")'));
    expect(gradleProperties, contains('android.builtInKotlin=false'));
    expect(gradleProperties, contains('android.newDsl=false'));
    expect(wrapper, contains('gradle-9.3.1-bin.zip'));
  });

  test(
    'production manifest declares only image and explicit recovery access',
    () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();

      expect(manifest, contains('android.permission.READ_MEDIA_IMAGES'));
      expect(
        manifest,
        contains('android.permission.READ_MEDIA_VISUAL_USER_SELECTED'),
      );
      expect(
        manifest,
        contains('READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"'),
      );
      expect(
        manifest,
        contains('WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"'),
      );
      expect(manifest, isNot(contains('READ_MEDIA_VIDEO')));
      expect(
        manifest,
        isNot(contains('android.permission.MANAGE_EXTERNAL_STORAGE')),
      );
      expect(manifest, isNot(contains('MANAGE_MEDIA')));
      expect(manifest, isNot(contains('android.permission.INTERNET')));
    },
  );

  test('Android 8–16 media access and MediaStore guards remain versioned', () {
    final access = File(
      'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
      'MediaAccessCoordinator.kt',
    ).readAsStringSync();
    final inventory = File(
      'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
      'MultiVolumeCurrentMediaQuery.kt',
    ).readAsStringSync();
    final metadata = File(
      'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
      'CurrentMediaMetadataQuery.kt',
    ).readAsStringSync();
    final trash = File(
      'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
      'VerifiedTrashQuery.kt',
    ).readAsStringSync();
    final deepStorage = File(
      'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
      'DeepStorageRecoveryQuery.kt',
    ).readAsStringSync();
    final restore = File(
      'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
      'DeepFileCopyRestorer.kt',
    ).readAsStringSync();

    // API 26–28 needs the legacy image read/write route; API 29–32 keeps the
    // read-only route; 33+ uses image-only media permission; 34+ adds selected
    // photo handling without requesting video, audio, or document permissions.
    expect(access, contains('Build.VERSION.SDK_INT <= Build.VERSION_CODES.P'));
    expect(access, contains('Manifest.permission.WRITE_EXTERNAL_STORAGE'));
    expect(access, contains('Build.VERSION.SDK_INT >= 33'));
    expect(access, contains('Manifest.permission.READ_MEDIA_IMAGES'));
    expect(access, contains('Build.VERSION.SDK_INT >= 34'));
    expect(access, contains('READ_MEDIA_VISUAL_USER_SELECTED'));

    // Android 10 guards volume and relative-path features; verified trash and
    // broad-storage APIs are only reached on Android 11+.
    expect(inventory, contains('Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q'));
    expect(metadata, contains('Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q'));
    expect(trash, contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.R'));
    expect(deepStorage, contains('Build.VERSION.SDK_INT >= Build.VERSION_CODES.R'));
    expect(deepStorage, contains('Environment.isExternalStorageManager()'));

    // API 26–28 restore requires legacy write access; API 29+ uses pending
    // MediaStore publication rather than calling pending-only columns early.
    expect(restore, contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.Q'));
    expect(restore, contains('Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q'));
  });
  test('thumbnail loading remains bounded and avoids full-image decoding', () {
    final loader = File(
      'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
      'BoundedThumbnailLoader.kt',
    ).readAsStringSync();
    final decoder = File(
      'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
      'BoundedFileThumbnailDecoder.kt',
    ).readAsStringSync();
    final inspector = File(
      'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
      'ImageSignatureInspector.kt',
    ).readAsStringSync();

    expect(loader, contains('coerceIn(1, 512)'));
    expect(loader, contains('resolver.loadThumbnail'));
    expect(loader, contains('MediaStore.Images.Thumbnails.getThumbnail'));
    expect(loader, isNot(contains('BitmapFactory')));
    expect(loader, isNot(contains('openInputStream')));
    expect(decoder, contains('inJustDecodeBounds = true'));
    expect(decoder, contains('inSampleSize = sample'));
    expect(inspector, contains('inJustDecodeBounds = true'));
    expect(
      inspector,
      contains('BitmapFactory.decodeStream(stream, null, options)'),
    );
  });

  test(
    'launcher uses the supplied artwork across fallbacks and adaptive icon',
    () {
      final adaptiveIcon = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();

      expect(adaptiveIcon, contains('<adaptive-icon'));
      expect(adaptiveIcon, contains('@mipmap/ic_launcher_foreground'));

      expect(
        File('android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png')
            .existsSync(),
        isTrue,
      );
    },
  );
}
