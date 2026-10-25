import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_tokens.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _sections = <(String, String)>[
    (
      'Information accessed and why',
      'When you start a scan, the app may read image content and related information such as names, file sizes, image dimensions, dates, media identifiers, storage locations, and Android content URIs. It uses this information locally to compare current media with recovery candidates, validate image content, show possible copies separately from items with Android deletion evidence, and carry out a restore that you initiate.\n\nA file’s absence from a library index is not treated as proof that it was deleted. The app does not promise that permanently deleted photos can generally be recovered. A photo is labeled verified deleted only when the app has supported deletion evidence, such as a matching Android system-trash record.',
    ),
    (
      'Permissions and user-selected folders',
      'Android may ask for photo-library access so the app can inspect accessible shared images and compare them with recovery records. On Android versions that support it, you can grant limited access to selected photos. A limited grant is not a full-library scan. If you decline library access, you can instead choose a folder through Android’s system folder picker; that scan is restricted to the folder and files you authorized. You can revoke photo access or a folder grant in Android settings.\n\nThe production app does not request Android’s All files access permission. Optional device-wide file traversal is not required for the standard MediaStore scan. The app does not use root access or scan other apps’ private directories.',
    ),
    (
      'Recovery Shield and restored files',
      'If you explicitly protect a photo with Recovery Shield, the app stores a verified private copy and its integrity metadata in app-private storage on your device. Shield copies are not uploaded by this app and are excluded from Android Auto Backup. You can remove them in Recovery Shield; clearing app data or uninstalling the app also removes app-private Shield data.\n\nA restore or save-a-copy action runs only after you choose it. It creates a new copy in shared media or a folder you authorize; it does not delete the source photo. The app keeps local restore-history metadata, such as the restored content URI, name, type, source, and time, so it can show your history. This history does not contain the restored image bytes.',
    ),
    (
      'Local storage and retention',
      'Scan results are held in memory while needed. To reduce repeat image inspection, the app may retain a bounded, app-private metadata cache containing storage-relative identifiers, file size and modification time, and detected image format or dimensions. Cache entries expire after 14 days and the persistent cache is capped. The app may also keep temporary image payloads in its app cache during permitted embedded-image inspection; these are bounded and are pruned by age and size. Temporary/cache data is not uploaded.\n\nApp preferences, recovery history, and Recovery Shield records stay in app-private storage. Android app-data clearing and uninstall remove app-private records and cache. Photos that you explicitly restore to shared storage are separate files and follow Android’s storage and backup behavior.',
    ),
    (
      'Sharing and third parties',
      'The app does not sell, rent, or share your photos or scan results with an app-operated server, advertiser, or analytics provider in the current implementation. Android’s operating system and the storage/media providers you use handle the requested local file access under their own terms. If the app later adds a network service, advertising, analytics, or another SDK, this policy and the Play Console Data safety declaration must be updated before release.',
    ),
    (
      'Your choices and contact',
      'You can decline or revoke photo permissions, choose only a folder, remove Recovery Shield copies, clear app data, or uninstall the app. For privacy questions or requests, contact the publisher using the developer email shown on the app’s official Google Play listing.',
    ),
    (
      'Changes',
      'If the app’s data practices change, this policy must be updated before those changes are released. The current policy should be published at the active privacy-policy URL on the Google Play listing and available from within the app.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy Policy')),
    body: SafeArea(
      child: ResponsiveContent(
        maxWidth: 760,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        child: ListView(
          children: [
            PremiumSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Photo Recovery & Restore',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Last updated October 18, 2026 · Android app · '
                    'com.photorecoveryrestore.app',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Photos and scan results are processed on this device. '
                    'The current implementation does not upload them to an '
                    'app-operated server.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final section in _sections) ...[
              PremiumSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.$1,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(section.$2),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    ),
  );
}
