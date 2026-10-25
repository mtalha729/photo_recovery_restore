import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  final buildFile = File('$root/android/app/build.gradle.kts');
  final manifestFile = File('$root/android/app/src/main/AndroidManifest.xml');
  final debugManifestFile = File(
    '$root/android/app/src/debug/AndroidManifest.xml',
  );
  final mediaMetadataFile = File(
    '$root/android/app/src/main/kotlin/com/photorecoveryrestore/app/CurrentMediaMetadataQuery.kt',
  );
  final thumbnailLoaderFile = File(
    '$root/android/app/src/main/kotlin/com/photorecoveryrestore/app/BoundedThumbnailLoader.kt',
  );
  final uriThumbnailDecoderFile = File(
    '$root/android/app/src/main/kotlin/com/photorecoveryrestore/app/BoundedUriThumbnailDecoder.kt',
  );
  final mediaAccessFile = File(
    '$root/android/app/src/main/kotlin/com/photorecoveryrestore/app/MediaAccessCoordinator.kt',
  );
  final trashFile = File(
    '$root/android/app/src/main/kotlin/com/photorecoveryrestore/app/VerifiedTrashQuery.kt',
  );
  final inventoryFile = File(
    '$root/android/app/src/main/kotlin/com/photorecoveryrestore/app/MultiVolumeCurrentMediaQuery.kt',
  );
  final deepStorageFile = File(
    '$root/android/app/src/main/kotlin/com/photorecoveryrestore/app/DeepStorageRecoveryQuery.kt',
  );

  test('Android configuration preserves API 26 and unrestricted APK ABIs', () {
    final build = buildFile.readAsStringSync();

    expect(build, contains('minSdk = 26'));
    expect(
      build,
      contains('compileSdk = maxOf(flutter.compileSdkVersion, 36)'),
    );
    expect(build, contains('targetSdk = maxOf(flutter.targetSdkVersion, 36)'));
    expect(build, isNot(matches(RegExp(r'ndk\s*\{[^}]*abiFilters'))));
    expect(build, contains('useLegacyPackaging = false'));
  });

  test('manifest has API-specific image permissions and exported launcher', () {
    final manifest = manifestFile.readAsStringSync();
    final debugManifest = debugManifestFile.readAsStringSync();

    expect(manifest, contains('READ_EXTERNAL_STORAGE'));
    expect(manifest, contains('READ_MEDIA_IMAGES'));
    expect(manifest, contains('android:exported="true"'));
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    expect(debugManifest, contains('MANAGE_EXTERNAL_STORAGE'));
  });

  test('Android 10-only metadata columns are guarded for API 26 devices', () {
    final source = mediaMetadataFile.readAsStringSync();

    expect(source, contains('Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q'));
    expect(source, contains('else storageVolumeName'));
  });

  test('Android 8 and 9 use legacy MediaStore pagination', () {
    final source = inventoryFile.readAsStringSync();
    final deepSource = deepStorageFile.readAsStringSync();
    expect(source, contains('Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q'));
    expect(source, contains('listOf("external")'));
    expect(
      deepSource,
      contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.Q -> "external"'),
    );
    expect(
      source,
      contains(
        'contentResolver.query(\n                collection,\n                projection,\n                selection,',
      ),
    );
    expect(source, contains('MediaStore returned no image cursor.'));
  });

  test('API 26 through 37 static compatibility matrix has a guarded path', () {
    final build = buildFile.readAsStringSync();
    final manifest = manifestFile.readAsStringSync();
    final access = mediaAccessFile.readAsStringSync();
    final trash = trashFile.readAsStringSync();

    for (final api in List<int>.generate(12, (index) => 26 + index)) {
      expect(
        build,
        contains('minSdk = 26'),
        reason: 'API $api must remain inside the supported range.',
      );
      if (api <= 28) {
        expect(manifest, contains('WRITE_EXTERNAL_STORAGE'));
        expect(
          access,
          contains('Build.VERSION.SDK_INT <= Build.VERSION_CODES.P'),
        );
      } else if (api <= 32) {
        expect(manifest, contains('READ_EXTERNAL_STORAGE'));
        expect(access, contains('Build.VERSION.SDK_INT <= 32'));
      } else {
        expect(manifest, contains('READ_MEDIA_IMAGES'));
        expect(access, contains('Build.VERSION.SDK_INT >= 33'));
      }
      if (api >= 34) {
        expect(manifest, contains('READ_MEDIA_VISUAL_USER_SELECTED'));
        expect(access, contains('Build.VERSION.SDK_INT >= 34'));
      }
      if (api < 30) {
        expect(
          trash,
          contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.R'),
        );
      } else {
        expect(trash, contains('MediaStore.QUERY_ARG_MATCH_TRASHED'));
      }
    }
  });

  test('Android 14+ initial request opts into selected-photo handling', () {
    final access = mediaAccessFile.readAsStringSync();
    final initialRequest = access.substring(
      access.indexOf('private fun permissionsFor('),
      access.indexOf('fun openSettings()'),
    );

    expect(initialRequest, contains('Manifest.permission.READ_MEDIA_IMAGES'));
    expect(
      initialRequest,
      contains('Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED'),
    );
    expect(initialRequest, contains('else -> arrayOf('));
  });

  test('legacy document thumbnails use bounded stream decoding', () {
    final source = thumbnailLoaderFile.readAsStringSync();
    final decoder = uriThumbnailDecoderFile.readAsStringSync();

    expect(source, contains('Build.VERSION.SDK_INT >= 29'));
    expect(source, contains('uriDecoder.decode(uri, width, height)'));
    expect(decoder, contains('inJustDecodeBounds = true'));
    expect(decoder, contains('inSampleSize = sample'));
  });
}
