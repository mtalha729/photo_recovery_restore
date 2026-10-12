import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release configuration avoids debug signing and enables shrinking', () {
    final buildFile = File('android/app/build.gradle.kts').readAsStringSync();

    expect(buildFile, contains('compileSdk = flutter.compileSdkVersion'));
    expect(buildFile, contains('minSdk = 26'));
    expect(buildFile, contains('targetSdk = flutter.targetSdkVersion'));
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
    expect(inventory, contains('MediaStore.MATCH_VISIBLE'));
    expect(metadata, contains('Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q'));
    expect(trash, contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.R'));
    expect(deepStorage, contains('Build.VERSION.SDK_INT >= Build.VERSION_CODES.R'));
    expect(deepStorage, contains('Environment.isExternalStorageManager()'));

    // API 26–28 restore requires legacy write access; API 29+ uses pending
    // MediaStore publication rather than calling pending-only columns early.
    expect(restore, contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.Q'));
    expect(restore, contains('Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q'));
  });
  test(
    'deep recovery broadens safe coverage without inventing deletion evidence',
    () {
      final deepStorage = File(
        'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
        'DeepStorageRecoveryQuery.kt',
      ).readAsStringSync();
      final signatures = File(
        'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
        'ImageSignatureInspector.kt',
      ).readAsStringSync();
      final carver = File(
        'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
        'EmbeddedImageCarver.kt',
      ).readAsStringSync();
      final cache = File(
        'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
        'DeepScanMetadataCache.kt',
      ).readAsStringSync();
      final restorer = File(
        'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
        'DeepFileCopyRestorer.kt',
      ).readAsStringSync();

      expect(deepStorage, contains('shallow = !thorough'));
      expect(deepStorage, contains('currentMediaKey'));
      expect(deepStorage, contains('displayName.lowercase()'));
      expect(deepStorage, contains('canonicalFile'));
      expect(deepStorage, contains('isWithin'));
      expect(deepStorage, contains('MAX_CARVED_RESULTS_PER_WORK'));
      expect(
        deepStorage,
        contains('if (extension in UNRELATED_EXTENSIONS) return thorough || highValue'),
      );
      expect(signatures, contains('JXL_CONTAINER'));
      expect(signatures, contains('JP2_CONTAINER'));
      expect(signatures, contains('return signature'));
      expect(carver, contains('val width: Int?'));
      expect(carver, contains('MAX_PAYLOAD_BYTES'));
      expect(cache, contains('signature.state != "valid"'));
      expect(cache, contains('relativePath.replace'));
      expect(cache, isNot(contains('relativePath.lowercase')));
      expect(restorer, contains('"jxl" -> "jxl"'));
      expect(restorer, contains('"jp2" -> "jp2"'));
      expect(deepStorage, isNot(contains('/dev/')));
    },
  );

  test('thumbnail loading remains bounded and avoids full-image decoding', () {
    final loader = File(
      'android/app/src/main/kotlin/com/photorecoveryrestore/app/'
      'BoundedThumbnailLoader.kt',
    ).readAsStringSync();

    expect(loader, contains('coerceIn(1, 512)'));
    expect(loader, contains('resolver.loadThumbnail'));
    expect(loader, contains('MediaStore.Images.Thumbnails.getThumbnail'));
    expect(loader, isNot(contains('BitmapFactory')));
    expect(loader, isNot(contains('openInputStream')));
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
