# Photo Recovery & Restore

A Flutter application for local photo recovery, restore, duplicate cleanup, and
Recovery Shield protection. The Android implementation uses MediaStore and
user-authorized Storage Access Framework folders; it does not bundle a photo
library or a third-party recovery SDK.

## Android build size

Do **not** use a debug APK as the size benchmark for this application. A Flutter
debug APK intentionally contains the Dart VM, service/debug tooling, unoptimized
Dart code, and—unless the build is split—native Flutter binaries for multiple
CPU architectures. A universal debug APK around 160 MB is therefore expected
and is not the size users receive from Google Play.

The release build in this repository already enables R8 code shrinking and
Android resource shrinking. The source tree also has no runtime pub packages or
application assets that would materially inflate an Android release APK; the
Flutter engine and ABI selection are the dominant size factors.

### Small direct-install APKs

From the repository root, build device-specific release APKs:

```bash
flutter clean
flutter pub get
flutter build apk --release --split-per-abi
```

The output is in `build/app/outputs/flutter-apk/`. Install the APK matching the
device:

- `app-arm64-v8a-release.apk` for almost all current physical phones
- `app-armeabi-v7a-release.apk` for older 32-bit ARM phones
- `app-x86_64-release.apk` for x86_64 emulators or devices

For a single arm64-only APK, use:

```bash
flutter build apk --release --target-platform android-arm64
```

The arm64 release APK is the artifact to compare with a 25–30 MB target. The
exact size depends on the Flutter SDK engine version and signing/build options,
so verify the produced file rather than relying on the debug APK size.

If a debuggable APK is required for testing on one arm64 phone, this avoids
packaging the other CPU architectures:

```bash
flutter build apk --debug --target-platform android-arm64
```

It will still be larger than release because the Dart VM and debug service must
remain present; reducing it to release size would remove the debugging
capabilities.

### Google Play upload

Use an Android App Bundle for Play distribution:

```bash
flutter build appbundle --release
```

Google Play serves only the ABI and resources required by each device. A bundle
is normally preferable to uploading a universal APK.

Before publishing, host `PRIVACY_POLICY.md` at a stable public HTTPS URL, add it
to the Play listing and keep the in-app privacy-policy screen current. Complete
the Play Console Photo and Video Permissions declaration for the core recovery
use case and the Data safety form from the final signed AAB. Never upload a
`debug` or `profile` build: those variants intentionally contain development
permissions and tooling that are absent from the production release.

### Inspect an artifact

```bash
du -h build/app/outputs/flutter-apk/*.apk
unzip -l build/app/outputs/flutter-apk/app-arm64-v8a-release.apk | sort -k1,1n | tail -20
```

A release build must remain non-debuggable, minified, and resource-shrunk. Do
not enable those release settings on the debug build if you need Flutter
breakpoints, hot reload, or the Dart service protocol; those features are the
reason debug builds cannot be made equivalent to release builds without losing
debug functionality.

## Recovery safety and coverage

The verified results list is populated only from MediaStore deletion evidence,
Recovery Shield records, or another explicit protected-deletion record. The
production build uses MediaStore and user-selected SAF folders; the broader
filesystem traversal is isolated to the internal debug variant and is not a
Play-upload permission. That traversal is user-authorized and bounded over
accessible shared storage and removable volumes. It can retain extensionless or
misnamed images,
common trash/cache/thumbnail and shared-app-media locations, and bounded image
payloads found inside approved containers.

Deep discoveries are shown as **Possible Copies**, never as deleted originals,
and current MediaStore media is excluded using exact volume/path/name/size
identities where available. Full-quality files, reduced-resolution copies,
thumbnails, corrupted files, and unavailable files remain separate states. The
scan does not read raw devices or partitions, enter `Android/data` or
`Android/obb`, access another app's restricted sandbox, or claim that an
accessible file was deleted without evidence.

## Development

```bash
flutter pub get
flutter analyze
flutter test
```

The Android package/application ID is `com.photorecoveryrestore.app`. Release
signing is intentionally supplied outside source control.
