# Automatic photo scanning and storage access

## Purpose

Photo Recovery & Restore needs to inspect accessible image records across
shared storage so it can distinguish currently present photos from potential
recovery candidates. MediaStore alone cannot enumerate every readable residual
copy, cache, thumbnail, or hidden shared-storage location. The scanner never
accesses `Android/data`, `Android/obb`, private app sandboxes, or storage that
Android has not made available to the app.

## Release configuration

The Play release manifest requests only the applicable image and legacy media
permissions. On Android 11 and newer it automatically scans MediaStore images
and supported trash records, then attempts bounded discovery of directly
readable shared image files across available volumes. Android can still hide
directories and non-media cache files under scoped storage. On Android 14
and newer, a selected-photos grant is treated as limited coverage; the app must
not describe it as a full-library or full-device scan.

The release manifest deliberately omits `MANAGE_EXTERNAL_STORAGE`. That means
an Android 11+ Play build can inspect only image files exposed by the granted
media permission; it cannot automatically read arbitrary non-media containers,
protected caches, or private app directories. It reports compactly when
locations were unavailable and preserves any copies already found.

On Android 8 and 9, the legacy storage permission permits bounded shared
storage traversal. Android 10 and later can restrict directory listings and
non-media files under scoped storage. The automatic thorough scan attempts
image and container inspection only where the operating system actually lets
the app open and read those files; it records denied directories separately.

## Development configuration

The debug and `internalRelease` manifests contain `MANAGE_EXTERNAL_STORAGE`
solely to test the bounded, automatic shared-storage traversal on devices
where the developer has manually enabled Android's Special app access. In
Android Studio, select the `internalRelease` Build Variant for a signed local
release-style APK; keep `release` selected for the Play artifact. The local
variant shows Android's access explanation before scanning when special
access has not yet been granted, and resumes the scan after the settings page.
Native code checks
`Environment.isExternalStorageManager()` before starting that traversal. It
does not assume the access is granted and it does not bypass Android storage
controls.

## Play assessment required before broad access

`MANAGE_EXTERNAL_STORAGE` is not included in a Play release by default. Google
Play requires broad shared-storage access to be essential to a user-facing core
function, to be declared, and to pass its access review. A recovery product may
need to argue that cross-folder discovery of residual image copies is essential
to its primary on-device restore function, but that is an assessment for the
publisher and Google Play—not an approval represented by this source code.

Before adding All Files Access to a release build, the publisher must complete
the current Play declaration, provide a clear in-app disclosure, obtain the
required approval, and inspect the merged release manifest. If approval is not
obtained, the MediaStore-only automatic scan remains the compliant release
behavior.

Google Play lists backup-and-restore apps among potentially permitted uses,
but only when automatic access to multiple external directories is essential
to the app's core function and the publisher passes Play's review. This app's
photo-recovery purpose is not an automatic approval. See the
[Google Play All files access policy](https://support.google.com/googleplay/android-developer/answer/10467955)
and [Android storage guidance](https://developer.android.com/training/data-storage/manage-all-files).
