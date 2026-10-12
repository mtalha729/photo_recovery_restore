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

- The Flutter Android defaults currently resolve to min SDK 26, compile SDK 36,
  and target SDK 36. API 26–28 behavior remains guarded in the platform code.
- Validate the final signed artifact on an API 26 device/emulator and current
  Android versions before release.

## Photo and storage access

- `READ_MEDIA_IMAGES` is used only for the core recovery workflow: inventorying
  accessible current images so existing media is excluded from recovery results,
  and analysing permitted image records. A Photo Picker selection alone cannot
  provide full-library visibility for that exclusion and analysis.
- Limited visual-media access is represented as limited access. The app must not
  claim a full scan, infer deletion, or present inaccessible media as deleted.
- Custom folders use user-authorized Storage Access Framework scopes. The app
  does not request All files access; it scans only images exposed by MediaStore
  and folders explicitly selected by the user.
- Main-manifest permissions are limited to `READ_MEDIA_IMAGES`,
  `READ_MEDIA_VISUAL_USER_SELECTED`, legacy `READ_EXTERNAL_STORAGE` through API
  32, and legacy `WRITE_EXTERNAL_STORAGE` through API 28. There is no all-files,
  video, manage-media, location, background, or network permission in the
  production manifest. Debug/profile-only Internet permission is not part of a
  release build.
- Review and submit the Play Console Photo and Video Permissions declaration for
  `READ_MEDIA_IMAGES`, explaining the core recovery/exclusion use case. Also
  review every permission in the final merged manifest and release artifact.
- No `MANAGE_EXTERNAL_STORAGE` declaration is present. Selected custom folders
  use the Storage Access Framework instead.

## Data safety and privacy

- Photos and recovery metadata are processed locally by the current app.
- Recovery Shield stores opted-in protected copies in local app-private storage;
  they are not uploaded by this app and are removed when the app is uninstalled.
- No cloud upload, ads, analytics SDK, or network feature is currently included.
- Before publishing, the app owner must complete Play Console Data safety,
  privacy-policy, permissions, and content declarations using the final binary
  and any services added after this audit. Do not make declarations based only
  on this document.

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
  install/update behavior, media-access states, SAF grant loss, Shield
  integrity, and restore failure cleanup on supported Android versions.
- Re-run the recovery accuracy benchmark and full test suite after any release
  dependency, manifest, permission, or signing change.
