import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_tokens.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy policy')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: ResponsiveContent(
          maxWidth: 760,
          child: PremiumSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Photo Recovery & Restore privacy policy',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Effective date: October 12, 2026',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                const _PolicySection(
                  title: 'Summary',
                  body:
                      'Photo Recovery & Restore is designed to process photo recovery data locally on your Android device. The app does not upload your photos, recovery copies, or photo metadata to a server, and it does not include advertising or analytics services.',
                ),
                const _PolicySection(
                  title: 'Information the app accesses',
                  body:
                      'When you grant Android photo access, the app reads the image records and limited metadata needed to find visible and system-trash records, compare current media, classify recovery results, and prevent an existing photo from being shown as deleted. When you choose a folder with Android Storage Access Framework, the app can read only that folder and its permitted descendants. Access is not used to browse unrelated apps or restricted Android data folders.',
                ),
                const _PolicySection(
                  title: 'How information is used',
                  body:
                      'Photo bytes and metadata are used only on the device to show recovery results, create a user-requested restored copy, or protect a copy in Recovery Shield. The app does not sell, rent, profile, or share this information with third parties.',
                ),
                const _PolicySection(
                  title: 'Recovery Shield',
                  body:
                      'If you choose Recovery Shield, the app stores a protected copy in private app storage on the device. Shield copies remain local, can be removed from the app, and are removed by Android when the app is uninstalled. Removing a Shield copy does not delete the original photo.',
                ),
                const _PolicySection(
                  title: 'Sharing and retention',
                  body:
                      'The app has no cloud upload or automatic sharing feature. Recovery results and temporary processing data remain on the device until they are cleared, replaced by normal app-cache cleanup, or removed with the app. A restored copy is published to the Android media library only after you request the restore operation.',
                ),
                const _PolicySection(
                  title: 'Your choices',
                  body:
                      'You can deny or later revoke photo permission, limit access to selected photos where Android provides that option, remove a persisted folder grant in Android settings, clear Recovery Shield copies, or uninstall the app. Revoking access can make some recovery features unavailable; the app does not treat inaccessible files as deleted.',
                ),
                const _PolicySection(
                  title: 'Children',
                  body:
                      'The app is not directed to children and does not knowingly collect personal information from children.',
                ),
                const _PolicySection(
                  title: 'Questions and changes',
                  body:
                      'For privacy questions or requests, use the developer support contact shown on the app’s Google Play listing. This policy may be updated when the app’s data practices change; the effective date above will be updated with material changes.',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(body, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}
