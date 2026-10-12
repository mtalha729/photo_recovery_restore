import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_colors.dart';
import '../../../app/design_system/foundations/app_tokens.dart';
import '../../media_access/media_access.dart';
import '../../recovery_shield_management/presentation/recovery_shield_screen.dart';
import '../../recovery_shield_management/recovery_shield_manager.dart';
import '../app_preferences.dart';
import 'privacy_policy_screen.dart';

abstract interface class StoreReviewIntent {
  Future<bool> requestReview();
}

class UnpublishedStoreReviewIntent implements StoreReviewIntent {
  const UnpublishedStoreReviewIntent();

  @override
  Future<bool> requestReview() async => false;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.preferences,
    required this.mediaAccess,
    required this.shieldManager,
    required this.onReplayOnboarding,
    this.storeReviewIntent = const UnpublishedStoreReviewIntent(),
    this.onSendFeedback,
    this.onShareApp,
    super.key,
  });

  final AppPreferencesController preferences;
  final MediaAccessCoordinator mediaAccess;
  final RecoveryShieldManager shieldManager;
  final VoidCallback onReplayOnboarding;
  final StoreReviewIntent storeReviewIntent;
  final VoidCallback? onSendFeedback;
  final VoidCallback? onShareApp;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  MediaAccessState? _access;
  RecoveryShieldSnapshot? _shield;
  String? _version;

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  Future<void> _load() async {
    final values = await Future.wait<Object>([
      widget.mediaAccess.getState(),
      widget.shieldManager.load(),
      widget.preferences.store.appVersion(),
    ]);
    if (!mounted) return;
    setState(() {
      _access = values[0] as MediaAccessState;
      _shield = values[1] as RecoveryShieldSnapshot;
      _version = values[2] as String;
    });
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _clearShield() async {
    final count = _shield?.protectedCount ?? 0;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Recovery Shield?'),
        content: Text(
          'This removes $count protected ${count == 1 ? 'copy' : 'copies'} from private app storage. Original photos are never deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear protected copies'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.shieldManager.clear();
    await _load();
  }

  void _openShield() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RecoveryShieldScreen(manager: widget.shieldManager),
      ),
    );
  }

  Future<void> _showShieldActions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shield_outlined),
                title: const Text('Manage Recovery Shield'),
                subtitle: const Text('Protect and manage your private copies.'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openShield();
                },
              ),
              if ((_shield?.protectedCount ?? 0) > 0)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Clear protected copies'),
                  subtitle: const Text('Original photos are never deleted.'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _clearShield();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestReview() async {
    final opened = await widget.storeReviewIntent.requestReview();
    if (!mounted || opened) return;
    _showMessage('Store review will be available after publication.');
  }

  void _showAbout() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Photo Recovery & Restore',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('Version ${_version ?? 'Unavailable'}'),
              const SizedBox(height: AppSpacing.md),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  widget.onReplayOnboarding();
                },
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Replay onboarding'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: SafeArea(
      child: ResponsiveContent(
        maxWidth: 720,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ListView(
          children: [
            Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Make the app work the way you prefer.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _SettingsSection(
              title: 'General',
              children: [
                _SettingsActionRow(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  subtitle: 'Choose your preferred theme',
                  trailing: _ThemePicker(
                    value: widget.preferences.state.themeMode,
                    onChanged: widget.preferences.setThemeMode,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _SettingsSection(
              title: 'Recovery & privacy',
              children: [
                _SettingsActionRow(
                  icon: Icons.photo_library_outlined,
                  title: 'Photo access',
                  subtitle: _accessSubtitle,
                  trailingText: _accessLabel,
                  onTap: widget.mediaAccess.openSettings,
                ),
                const SizedBox(height: AppSpacing.sm),
                _SettingsActionRow(
                  icon: Icons.shield_outlined,
                  color: AppColors.protection,
                  title: 'Recovery Shield',
                  subtitle: _shieldSubtitle,
                  onTap: _showShieldActions,
                ),
                const SizedBox(height: AppSpacing.sm),
                _SettingsActionRow(
                  icon: Icons.privacy_tip_outlined,
                  color: AppColors.accent,
                  title: 'Privacy & permissions',
                  subtitle: 'Manage Android photo permissions',
                  onTap: widget.mediaAccess.openSettings,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _SettingsSection(
              title: 'Support',
              children: [
                _SettingsActionRow(
                  icon: Icons.star_outline_rounded,
                  color: AppColors.warning,
                  title: 'Rate us',
                  subtitle: 'Share your experience',
                  onTap: _requestReview,
                ),
                const SizedBox(height: AppSpacing.sm),
                _SettingsActionRow(
                  icon: Icons.mail_outline_rounded,
                  title: 'Send feedback',
                  subtitle: 'Help us improve the app',
                  onTap:
                      widget.onSendFeedback ??
                      () => _showMessage('Feedback contact is not configured.'),
                ),
                const SizedBox(height: AppSpacing.sm),
                _SettingsActionRow(
                  icon: Icons.ios_share_rounded,
                  title: 'Share app',
                  subtitle: 'Tell someone about this app',
                  onTap:
                      widget.onShareApp ??
                      () => _showMessage(
                        'Sharing will be available after publication.',
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _SettingsSection(
              title: 'About',
              children: [
                _SettingsActionRow(
                  icon: Icons.policy_outlined,
                  title: 'Privacy policy',
                  subtitle: 'Read how your data is handled',
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const PrivacyPolicyScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _SettingsActionRow(
                  icon: Icons.info_outline_rounded,
                  title: 'About',
                  subtitle: 'Version ${_version ?? 'Loading…'}',
                  onTap: _showAbout,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  String get _accessLabel => switch (_access?.status) {
    MediaAccessStatus.fullAccess => 'Full',
    MediaAccessStatus.limitedSelectedAccess => 'Limited',
    MediaAccessStatus.notRequired => 'Not required',
    MediaAccessStatus.denied || MediaAccessStatus.settingsRequired => 'Denied',
    MediaAccessStatus.unsupported => 'Unsupported',
    _ => 'Unavailable',
  };

  String get _accessSubtitle => switch (_access?.status) {
    MediaAccessStatus.fullAccess => 'Full photo library access is available',
    MediaAccessStatus.limitedSelectedAccess =>
      'Only selected photos are available',
    MediaAccessStatus.denied ||
    MediaAccessStatus.settingsRequired => 'Photo access is currently denied',
    _ => 'Review Android photo access',
  };

  String get _shieldSubtitle {
    final snapshot = _shield;
    if (snapshot == null) return 'Checking protected copies…';
    final count = snapshot.protectedCount;
    if (count == 0) return 'No protected photos yet';
    return '$count protected ${count == 1 ? 'photo' : 'photos'}';
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: AppSpacing.sm),
      ...children,
    ],
  );
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color = AppColors.primary,
    this.trailing,
    this.trailingText,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget? trailing;
  final String? trailingText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Color.alphaBlend(
      color.withValues(alpha: isDark ? .13 : .06),
      isDark ? const Color(0xFF111B2F) : const Color(0xFFF9FBFF),
    );
    final border = Color.alphaBlend(
      color.withValues(alpha: isDark ? .22 : .12),
      isDark ? const Color(0xFF2E405E) : const Color(0xFFD9E3F2),
    );
    return Semantics(
      button: onTap != null,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: border, width: 1.1),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? const Color(0xFF000000).withValues(alpha: .11)
                      : AppColors.primary.withValues(alpha: .035),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                _SettingsIconBadge(icon: icon, color: color),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  trailing!,
                ] else if (trailingText != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 82),
                    child: Text(
                      trailingText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: color, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Icon(Icons.chevron_right_rounded, color: color),
                ] else if (onTap != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(Icons.chevron_right_rounded, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsIconBadge extends StatelessWidget {
  const _SettingsIconBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .22 : .12,
      ),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Icon(icon, color: color),
  );
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonHideUnderline(
    child: DropdownButton<ThemeMode>(
      value: value,
      borderRadius: BorderRadius.circular(16),
      icon: const Icon(Icons.expand_more_rounded),
      items: const [
        DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
        DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
        DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    ),
  );
}
