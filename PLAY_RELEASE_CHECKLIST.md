# Google Play release checklist

This checklist describes the current application behavior and must be reviewed
against the final signed release artifact before publishing. It is not a claim
that Google Play approval is guaranteed.

## Release identity and signing

- Application ID and namespace are set to
  `com.photorecoveryrestore.app`. Treat this as permanent before the first Play
  upload; changing it later creates a different Android app identity.
- Release builds are intentionally not debug-signed. Configure an upload key and
  release signing outside source control; do not commit keystores, passwords, or
  signing properties.
- Current version is `1.0.0+1`. Increment the version code for every Play upload.

## SDK support

- Google Play requires new apps and app updates submitted from 2026-08-31 to
  target Android 16 (API 36) or higher. The app currently delegates `targetSdk`
  to `flutter.targetSdkVersion`; verify the final release AAB actually reports
  target 36 or higher. Do not rely on this checklist as a substitute for the
  artifact check.
- The configured minimum SDK is 26. Validate the final signed artifact on an
  API 26 device/emulator and current Android versions before release.

## Photo and storage access

- `READ_MEDIA_IMAGES` supports the core recovery workflow by allowing the app to
  inventory accessible current images and avoid presenting current media as
  deleted. This is broad photo access: complete the Play Console Photo and Video
  Permissions declaration and obtain approval before release. Explain why
  full-library visibility is essential to this core workflow; approval is not
  guaranteed.
- Android 14+ limited photo access is represented as limited access. The app's
  disclosure tells users that limited access is not a full-library scan. Keep
  results and marketing honest about that limitation.
- The main manifest requests `READ_MEDIA_IMAGES`,
  `READ_MEDIA_VISUAL_USER_SELECTED`, legacy `READ_EXTERNAL_STORAGE` through API
  32, and legacy `WRITE_EXTERNAL_STORAGE` through API 28. It does not request
  video, manage-media, location, background, or network access.
- `MANAGE_EXTERNAL_STORAGE` appears only in the debug manifest for local
  testing; it is absent from the main manifest. Build/upload only the signed
  `release` AAB and inspect its merged manifest to confirm this permission is
  absent. Do not add All files access to the Play build without a separate
  policy review and Play approval. The current release deep file-walk is not
  available on Android 11+ without that permission; MediaStore recovery remains
  separate. Do not add production All files access without a separate policy
  review and Play approval.
- Debug/profile-only `INTERNET` permission is not part of the release manifest.
  Recheck the final merged manifest and every packaged SDK before submission.

## Data safety and privacy

- Photo inspection and recovery processing are local in the current source; no
  app upload, ads, analytics SDK, or network feature is included. Confirm this
  against the final binary and any later-added SDKs before declaring Data safety.
- `android:allowBackup="false"` is set in the main manifest to keep app-private
  preferences and scan metadata out of Android Auto Backup. This does not control
  backup behavior for photos the user explicitly restores to shared storage.
- Recovery Shield stores opted-in protected copies in `noBackupFilesDir`; they
  are not uploaded by this app and are removed when the app is uninstalled.
- **Release requirement:** the in-app Privacy Policy screen and `PRIVACY_POLICY.md`
  now describe the current local-processing behavior, photo access, Recovery
  Shield, metadata/cache retention, and user controls. Before release, the
  publisher must host the final policy at an active, publicly accessible HTTPS
  URL, enter that URL in Play Console, and ensure the official listing contains
  a monitored privacy contact email. The developer identity/contact and public
  URL cannot be inferred safely from this source tree. Complete the Play Console
  Data safety form against the final artifact; do not copy a declaration without
  verifying every included SDK and data flow.
- Complete all Play Console permissions, Data safety, privacy-policy, target
  audience, content-rating, and store-listing declarations against the final
  signed artifact. This checklist is not evidence of Play approval.

## Image memory and performance

- Media discovery and classification are metadata-only; they do not decode
  full-resolution images or hash the whole library.
- UI thumbnail requests are capped at 512 px. Android 10+ uses bounded
  `ContentResolver.loadThumbnail`; Android 8–9 uses the MediaStore thumbnail
  cache and scales the result down to the requested bound. There is no
  full-resolution `BitmapFactory` fallback or unbounded bitmap cache.

## Release optimization and final validation

- Release minification and resource shrinking are enabled with the optimized
  Android default R8 rules. With the current AGP 9.1 setup, optimized resource
  shrinking is applied when resource shrinking is enabled.
- Build and inspect a signed release AAB outside this milestone. Exercise R8,
  install/update behavior, media-access states, Recovery Shield integrity, and
  restore failure cleanup on supported Android versions.
- Re-run the recovery accuracy benchmark and full test suite after any release
  dependency, manifest, permission, or signing change.
