# Privacy Policy — Photo Recovery & Restore

**Last updated: October 18, 2026**

This policy applies to the Android application **Photo Recovery & Restore** (`com.photorecoveryrestore.app`). The publisher is the developer identified on the app's official Google Play listing. Privacy questions can be sent through the developer contact email on that listing.

## Summary

Photo Recovery & Restore processes photos and related file information on your device to find Android trash records and accessible image copies, exclude existing media, and save a copy when you ask it to. The app does not upload photos or scan results to an app-operated server. It has no account, advertising, or analytics service in the current release implementation.

## Information accessed and why

When you start a scan, the app may read image content and related information such as names, file sizes, image dimensions, dates, media identifiers, storage locations, and Android content URIs. It uses this information locally to compare current media with recovery candidates, validate image content, show possible copies separately from items with Android deletion evidence, and carry out a restore that you initiate.

A file's absence from a library index is not treated as proof that it was deleted. The app does not promise that permanently deleted photos can generally be recovered. A photo is labeled verified deleted only when the app has supported deletion evidence, such as a matching Android system-trash record.

## Permissions and user-selected folders

Android may ask for photo-library access so the app can inspect accessible shared images and compare them with recovery records. On Android versions that support it, you can grant limited access to selected photos. A limited grant is not a full-library scan. If you decline library access, you can instead choose a folder through Android's system folder picker; that scan is restricted to the folder and files you authorized. You can revoke photo access or a folder grant in Android settings.

The production app does not request Android's All files access permission. Optional device-wide file traversal is not required for the standard MediaStore scan. The app does not use root access or scan other apps' private directories.

## Recovery Shield and restored files

If you explicitly protect a photo with Recovery Shield, the app stores a verified private copy and its integrity metadata in app-private storage on your device. Shield copies are not uploaded by this app and are excluded from Android Auto Backup. You can remove them in Recovery Shield; clearing app data or uninstalling the app also removes app-private Shield data.

A restore or save-a-copy action runs only after you choose it. It creates a new copy in shared media or a folder you authorize; it does not delete the source photo. The app keeps local restore-history metadata, such as the restored content URI, name, type, source, and time, so it can show your history. This history does not contain the restored image bytes.

## Local storage and retention

Scan results are held in memory while needed. To reduce repeat image inspection, the app may retain a bounded, app-private metadata cache containing storage-relative identifiers, file size and modification time, and detected image format or dimensions. Cache entries expire after 14 days and the persistent cache is capped. The app may also keep temporary image payloads in its app cache during permitted embedded-image inspection; these are bounded and are pruned by age and size. Temporary/cache data is not uploaded.

App preferences, recovery history, and Recovery Shield records stay in app-private storage. Android app-data clearing and uninstall remove app-private records and cache. Photos that you explicitly restore to shared storage are separate files and follow Android's storage and backup behavior.

## Sharing and third parties

The app does not sell, rent, or share your photos or scan results with an app-operated server, advertiser, or analytics provider in the current implementation. Android's operating system and the storage/media providers you use handle the requested local file access under their own terms. If you later add a network service, advertising, analytics, or another SDK, this policy and the Play Console Data safety declaration must be updated before release.

## Your choices and contact

You can decline or revoke photo permissions, choose only a folder, remove Recovery Shield copies, clear app data, or uninstall the app. You can contact the publisher about privacy using the developer email shown on the official Google Play listing for this app.

## Changes

If the app's data practices change, this policy must be updated before those changes are released. The current policy should be published at the active privacy-policy URL on the Google Play listing and available from within the app.
