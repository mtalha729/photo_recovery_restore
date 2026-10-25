# Photo Recovery & Restore

A Flutter Android app for checking Android's accessible media and restoring user-authorized image copies. Photo content is processed on-device in the current implementation.

## Recovery boundaries

- **Recover Photos** is the single primary entry to the `PhotoRecoveryEngine` and thorough recovery profile. It starts its permitted MediaStore scan automatically after the applicable photo permission is granted; selecting a folder is never required for the normal recovery flow.
- The scan uses Android media access and verified MediaStore trash evidence. A file is never called deleted only because it is missing from an index; existing photos, verified deletions, and possible copies stay distinct.
- Optional whole-storage traversal is not required for the standard MediaStore scan. Do not add `MANAGE_EXTERNAL_STORAGE` to the production manifest as a shortcut; keep access scoped to the media and explicit user actions the app needs.
- `READ_MEDIA_IMAGES` remains in the production app for the full-library workflow. Complete the Google Play Photo and Video Permissions declaration and obtain any required approval before release; approval is not guaranteed.

## Run and test on Android

Android method channels, MediaStore queries, and native restore code cannot be exercised with **Windows (desktop)** selected as the Flutter run target. Use an Android emulator or a USB-connected Android phone:

1. Configure the Flutter SDK in Android Studio and run `flutter pub get`. For AGP 9.1.1, use Gradle JDK 21 if Android Studio reports a JVM compatibility problem; Gradle JDK is a setting, not a reason to download Android Studio again.
2. Select an Android emulator/device in the device selector (not Windows desktop).
3. Run the app and start recovery from the single **Recover Photos** entry. If full-library access is declined, the automatic scan continues only for the photos Android makes available; it must not claim full-device coverage.
4. Verify that current photos are excluded, only candidates with deletion evidence are labeled deleted, and a restored copy is reported only after native integrity checks succeed.

## Windows build and installation checks

The Android module keeps `minSdk = 26` and does not restrict `ndk.abiFilters`, so a universal APK can include Flutter's ARMv7, ARM64, and x86_64 native libraries. A local `android/signing.properties` file supplies the release key. Without it, a release artifact is unsigned and cannot be installed as a normal APK; use the debug variant for local tests or configure the existing release/upload key. Never upload a debug-key artifact to Play.

### Build from the Android folder in Android Studio

Keep the complete `photo_recovery_restore` folder together: `android/` needs its sibling `lib/` and `pubspec.yaml` (plus any assets declared there). Open **`photo_recovery_restore/android`** in Android Studio, not a separately copied `android` folder. The included Gradle wrapper and Android Gradle files are required; `.gradle/` and `build/` are disposable caches and are not needed in a source ZIP.

Before the first Gradle sync, make sure `android/local.properties` contains your actual `sdk.dir` and `flutter.sdk` paths. Android Studio may write `sdk.dir`; if `flutter.sdk` is missing, copy `android/local.properties.example` to `android/local.properties` and replace both placeholder paths. Do not commit or export `local.properties`. From Android Studio's terminal, run `flutter pub get` in the parent `photo_recovery_restore` folder once after extraction or dependency changes. Set the Gradle JDK to 21 if your Android Studio installation does not select it automatically.

In Android Studio, choose the **debug** build variant for a local device test or configure `android/signing.properties` with the existing signing key before choosing **release**, then use **Build > Build Bundle(s) / APK(s) > Build APK(s)**. Android Studio's completion notification gives the APK path. An unsigned release APK is not installable; do not use a new key to update an app signed with a different certificate. No folder picker or separate Flutter-project window is required to start Recover Photos after installation.

### Release signing and command-line alternative

Create `android/signing.properties` outside source control using the existing upload/release key before either release command:

```properties
storeFile=C:\\keys\\photo-recovery-upload.jks
storePassword=your-store-password
keyAlias=your-key-alias
keyPassword=your-key-password
```

From Windows Command Prompt, create a universal test APK:

```bat
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm,android-arm64,android-x64
```

For ABI-specific APKs, let Flutter configure splitting instead of adding `splits.abi` or `ndk.abiFilters` to the Gradle file:

```bat
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64
```

For a Google Play upload bundle:

```bat
flutter build appbundle --release --target-platform android-arm,android-arm64,android-x64
```

The split command produces ARMv7, ARM64, and x86_64 APKs without a universal APK. Use the signed Android App Bundle for Play distribution; its ABI and density splits are configured in Gradle. Before release, run Flutter analysis/tests and build the signed Android App Bundle on a configured Android toolchain. Inspect the final merged release manifest and artifact; the artifact should target API 36 or higher for Play submissions made from August 31, 2026 onward. The sandbox source review has not verified a build, signed artifact, or Play approval.

An update can install only when its application ID and signing certificate match the already installed app and its version code is not lower. Check the installed signing certificate and back up any app-private data before considering removal; uninstalling removes that data. Prefer rebuilding with the original signing key and a higher version code. Do not change the application ID or replace the production signing identity merely to work around this condition.

## Play Console release checks

- The app opens an in-app Privacy Policy screen and `PRIVACY_POLICY.md` is the hostable copy. Before release, publish the policy at an active public HTTPS URL, add that URL and a monitored contact email to the official Play listing, and complete the Data safety, photo-permission, content, target-audience, and store-listing declarations against the final artifact.
- Keep the upload keystore and passwords outside source control. Do not commit local SDK paths, user media, build output, or generated APK/AAB files.
- Recheck every permission in the merged release manifest. A debug-only permission or source-level manifest review is not a substitute for inspecting the signed release artifact.
