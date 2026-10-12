import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_colors.dart';
import '../../../app/design_system/foundations/app_tokens.dart';
import '../../device_storage/device_storage.dart';

enum HomeRecoveryState { loading, empty }

abstract final class _HomeCardRadii {
  static const storage = 30.0;
  static const source = 28.0;
  static const icon = 22.0;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.onRecoverPhotos,
    required this.onDeepPhotoRecovery,
    required this.onSettings,
    required this.onManageShield,
    required this.onRecoveredPhotos,
    required this.onDuplicatePhotos,
    required this.onOldPhotos,
    required this.onLargePhotos,
    this.recoveryState = HomeRecoveryState.empty,
    this.storageReader,
    super.key,
  });

  final VoidCallback onRecoverPhotos;
  final VoidCallback onDeepPhotoRecovery;
  final VoidCallback onSettings;
  final VoidCallback onManageShield;
  final VoidCallback onRecoveredPhotos;
  final VoidCallback onDuplicatePhotos;
  final VoidCallback onOldPhotos;
  final VoidCallback onLargePhotos;
  final HomeRecoveryState recoveryState;
  final DeviceStorageReader? storageReader;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DeviceStorageReader _storageReader =
      widget.storageReader ?? PlatformDeviceStorageReader();
  DeviceStorageSnapshot? _storage;
  bool _storageLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStorage();
  }

  Future<void> _loadStorage() async {
    final snapshot = await _storageReader.read();
    if (!mounted) return;
    setState(() {
      _storage = snapshot;
      _storageLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: CustomScrollView(
      key: const PageStorageKey('home-scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: ResponsiveContent(
            maxWidth: 920,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(onSettings: widget.onSettings),
                const SizedBox(height: AppSpacing.md),
                _StorageOverview(storage: _storage, isLoading: _storageLoading),
                const SizedBox(height: AppSpacing.md),
                const AppSectionHeader(
                  title: 'Recover photos',
                  description: 'Choose a safe photo recovery scan.',
                ),
                const SizedBox(height: AppSpacing.sm),
                _RecoveryTypeGrid(
                  onRecoverPhotos: widget.onRecoverPhotos,
                  onDeepPhotoRecovery: widget.onDeepPhotoRecovery,
                  onRecoveredPhotos: widget.onRecoveredPhotos,
                ),
                const SizedBox(height: AppSpacing.lg),
                const AppSectionHeader(
                  title: 'Smart Cleanup',
                  description: 'Helpful photo tools, when available.',
                ),
                const SizedBox(height: AppSpacing.sm),
                _CleanupGrid(
                  onDuplicatePhotos: widget.onDuplicatePhotos,
                  onOldPhotos: widget.onOldPhotos,
                  onLargePhotos: widget.onLargePhotos,
                ),
                const SizedBox(height: AppSpacing.md),
                _ShieldEntryCard(onPressed: widget.onManageShield),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.headlineSmall,
            children: const [
              TextSpan(text: 'Photo'),
              TextSpan(
                text: 'Recovery',
                style: TextStyle(color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
      AccessibleIconAction(
        icon: Icons.settings_rounded,
        label: 'Open settings',
        onPressed: onSettings,
      ),
    ],
  );
}

class _StorageOverview extends StatelessWidget {
  const _StorageOverview({required this.storage, required this.isLoading});
  final DeviceStorageSnapshot? storage;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fraction = storage?.usedFraction ?? 0;
    final foreground = isDark
        ? const Color(0xFFF4F7FF)
        : const Color(0xFF15213A);
    final muted = isDark ? const Color(0xFFAAB8D6) : const Color(0xFF60708D);
    return Container(
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_HomeCardRadii.storage),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF18284B), Color(0xFF111C35)]
              : const [Color(0xFFEEF3FF), Color(0xFFF9FBFF)],
        ),
        border: Border.all(
            color: isDark ? const Color(0xFF405B8D) : const Color(0xFFCCD9F2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0xFF000000).withValues(alpha: .16)
                : AppColors.primary.withValues(alpha: .055),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: AppMotion.durationFor(
              reduceMotion: MediaQuery.disableAnimationsOf(context),
              duration: AppMotion.fast,
            ),
            curve: AppMotion.standardCurve,
            builder: (context, value, _) => _StorageRing(
              value: value,
              textColor: foreground,
              trackColor: isDark ? const Color(0xFF263758) : Colors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Storage details',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: foreground),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  isLoading
                      ? 'Checking available space…'
                      : storage == null
                      ? 'Storage details are unavailable.'
                      : '${_formatBytes(storage!.usedBytes)} used of ${_formatBytes(storage!.totalBytes)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageRing extends StatelessWidget {
  const _StorageRing({
    required this.value,
    required this.textColor,
    required this.trackColor,
  });
  final double value;
  final Color textColor;
  final Color trackColor;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Device storage ${((value.clamp(0, 1)) * 100).round()} percent used',
    child: SizedBox(
      width: 82,
      height: 82,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(82),
            painter: _StorageRingPainter(
              value: value.clamp(0, 1),
              trackColor: trackColor,
            ),
          ),
          Text(
            '${(value.clamp(0, 1) * 100).round()}%',
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: textColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _StorageRingPainter extends CustomPainter {
  const _StorageRingPainter({required this.value, required this.trackColor});

  final double value;
  final Color trackColor;

  static const _colors = [
    Color(0xFFF79009),
    Color(0xFFF0448B),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFFA3E635),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 8.0;
    final bounds = Offset.zero & size;
    final arcBounds = bounds.deflate(strokeWidth / 2);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcBounds, -math.pi / 2, math.pi * 2, false, track);

    final sweep = math.pi * 2 * value;
    if (sweep <= 0) return;
    const gap = 0.055;
    final segment = sweep / _colors.length;
    for (var index = 0; index < _colors.length; index++) {
      final start = -math.pi / 2 + segment * index;
      final length = math.max(0.0, segment - gap);
      if (length <= 0) continue;
      final paint = Paint()
        ..color = _colors[index]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(arcBounds, start, length, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StorageRingPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.trackColor != trackColor;
}

class _RecoveryTypeGrid extends StatelessWidget {
  const _RecoveryTypeGrid({
    required this.onRecoverPhotos,
    required this.onDeepPhotoRecovery,
    required this.onRecoveredPhotos,
  });
  final VoidCallback onRecoverPhotos;
  final VoidCallback onDeepPhotoRecovery;
  final VoidCallback onRecoveredPhotos;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _PrimaryRecoveryCard(onPressed: onDeepPhotoRecovery),
      const SizedBox(height: AppSpacing.md),
      Row(
        key: const ValueKey('recover-and-history-row'),
        children: [
          Expanded(
            child: _RecoveryTypeTile(
              type: _RecoveryType.photos,
              onPressed: onRecoverPhotos,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _RecoveredItemsCard(compact: true, onPressed: onRecoveredPhotos)),
        ],
      ),
    ],
  );
}

class _PrimaryRecoveryCard extends StatelessWidget {
  const _PrimaryRecoveryCard({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.25;
    return Semantics(
      button: true,
      label: 'Start Deep Photo Recovery',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(_HomeCardRadii.source),
          child: Ink(
            height: largeText ? 104 : 72,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111C35) : const Color(0xFFF7F9FF),
              borderRadius: BorderRadius.circular(_HomeCardRadii.source),
              border: Border.all(
                color: isDark ? const Color(0xFF3A5280) : const Color(0xFFD3DDF1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 88,
                  height: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: isDark ? .22 : .11),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(_HomeCardRadii.source),
                    ),
                  ),
                  child: const Icon(Icons.manage_search_rounded, size: 30, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Deep Photo Recovery', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      Text('Search accessible photos', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Icon(Icons.arrow_forward_ios_rounded, size: 20, color: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
int _compactColumns(BuildContext context, double width) {
  final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
  if (largeText || width < 340) return 1;
  if (width >= 760) return 4;
  if (width >= 540) return 3;
  return 2;
}

// ignore: unused_element
double _compactCardHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) > 1.3 ? 156 : 116;

// This application currently implements photo recovery only. Keeping empty
// video/audio/file actions visible would imply a capability that does not exist.
enum _RecoveryType { photos }

class _RecoveryTypeTile extends StatelessWidget {
  const _RecoveryTypeTile({required this.type, required this.onPressed});
  final _RecoveryType type;
  final VoidCallback? onPressed;

  Color get _color => switch (type) {
    _RecoveryType.photos => AppColors.protection,
  };

  String get _title => switch (type) {
    _RecoveryType.photos => 'Recover Photos',
  };

  IconData get _icon => switch (type) {
    _RecoveryType.photos => Icons.photo_library_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.25;
    final surface = Color.alphaBlend(
      _color.withValues(alpha: isDark ? .14 : .065),
      isDark ? const Color(0xFF101A2E) : const Color(0xFFF9FBFF),
    );
    final border = Color.alphaBlend(
      _color.withValues(alpha: isDark ? .24 : .14),
      isDark ? const Color(0xFF2D405E) : const Color(0xFFD8E2F2),
    );
    return Semantics(
      button: true,
      label: onPressed == null ? '$_title, unavailable' : _title,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(_HomeCardRadii.source),
          child: Ink(
            key: const ValueKey('recover-photos-card'),
            height: largeText ? 104 : 72,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(_HomeCardRadii.source),
              border: Border.all(color: border, width: 1.15),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? const Color(0xFF000000).withValues(alpha: .13)
                      : AppColors.primary.withValues(alpha: .045),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _color.withValues(alpha: isDark ? .23 : .13),
                        borderRadius: BorderRadius.circular(_HomeCardRadii.icon),
                      ),
                      child: Icon(
                        _icon,
                        size: AppIconSizes.medium,
                        color: _color,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: AppIconSizes.medium,
                      color: _color,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShieldEntryCard extends StatelessWidget {
  const _ShieldEntryCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = AppColors.protection;
    return Semantics(
      button: true,
      label: 'Open Recovery Shield',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(_HomeCardRadii.source),
          child: Ink(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? .13 : .07),
              borderRadius: BorderRadius.circular(_HomeCardRadii.source),
              border: Border.all(
                color: color.withValues(alpha: isDark ? .30 : .20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? .24 : .13),
                    borderRadius: BorderRadius.circular(_HomeCardRadii.icon),
                  ),
                  child: Icon(Icons.shield_outlined, color: color),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recovery Shield', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Keep private copies of photos you choose',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _RecoveredItemsCard extends StatelessWidget {
  const _RecoveredItemsCard({this.compact = false, required this.onPressed});
  final bool compact;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => _CompactRecoveredTile(onPressed: onPressed);
}

class _CompactRecoveredTile extends StatelessWidget {
  const _CompactRecoveredTile({required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.25;
    return Semantics(button: true, label: 'Recovered Photos', child: Material(color: Colors.transparent, child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(_HomeCardRadii.source),
      child: Container(
        key: const ValueKey('recovered-photos-card'), height: largeText ? 104 : 72,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
        decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: isDark ? .14 : .07), borderRadius: BorderRadius.circular(_HomeCardRadii.source), border: Border.all(color: AppColors.accent.withValues(alpha: isDark ? .27 : .18))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(width: 32, height: 32, alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: isDark ? .23 : .13), borderRadius: BorderRadius.circular(_HomeCardRadii.icon)), child: const Icon(Icons.history_rounded, color: AppColors.accent)),
            const Icon(Icons.arrow_forward_rounded, color: AppColors.accent),
          ]),
          const Spacer(),
          Text('Recovered Photos', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ]),
      ),
    )));
  }
}

// ignore: unused_element
class _CleanupGrid extends StatelessWidget {
  const _CleanupGrid({required this.onDuplicatePhotos, required this.onOldPhotos, required this.onLargePhotos});
  final VoidCallback onDuplicatePhotos;
  final VoidCallback onOldPhotos;
  final VoidCallback onLargePhotos;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.textScalerOf(context).scale(1) > 1.25 ? 154 : 110,
    child: ListView.separated(
      key: const ValueKey('cleanup-scroll'),
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      itemCount: _CleanupType.values.length,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
      itemBuilder: (context, index) {
        final type = _CleanupType.values[index];
        final action = switch (type) {
          _CleanupType.duplicatePhotos => onDuplicatePhotos,
          _CleanupType.oldPhotos => onOldPhotos,
          _CleanupType.largePhotos => onLargePhotos,
        };
        return SizedBox(width: 150, child: _CompactCleanupCard(type: type, onPressed: action));
      },
    ),
  );
}

enum _CleanupType { duplicatePhotos, oldPhotos, largePhotos }

class _CompactCleanupCard extends StatelessWidget {
  const _CompactCleanupCard({required this.type, required this.onPressed});
  final _CleanupType type;
  final VoidCallback onPressed;

  String get title => switch (type) {
    _CleanupType.duplicatePhotos => 'Duplicate Photos',
    _CleanupType.oldPhotos => 'Old Photos',
    _CleanupType.largePhotos => 'Large Photos',
  };
  IconData get icon => switch (type) {
    _CleanupType.duplicatePhotos => Icons.collections_outlined,
    _CleanupType.oldPhotos => Icons.photo_library_outlined,
    _CleanupType.largePhotos => Icons.photo_size_select_large_outlined,
  };
  Color get color => switch (type) {
    _CleanupType.duplicatePhotos => const Color(0xFF7664E8),
    _CleanupType.oldPhotos => AppColors.protection,
    _CleanupType.largePhotos => AppColors.accent,
  };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: title,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(_HomeCardRadii.source),
          child: Ink(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: color.withValues(alpha: dark ? .14 : .065),
              borderRadius: BorderRadius.circular(_HomeCardRadii.source),
              border: Border.all(color: color.withValues(alpha: dark ? .28 : .18)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 34, height: 34, alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: dark ? .24 : .13), borderRadius: BorderRadius.circular(_HomeCardRadii.icon)),
                child: Icon(icon, size: AppIconSizes.small, color: color),
              ),
              const Spacer(),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xxs),
              Row(children: [
                Expanded(child: Text('Review photos', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color))),
                Icon(Icons.arrow_forward_rounded, size: AppIconSizes.small, color: color),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
String _formatBytes(int value) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var amount = value.toDouble();
  var unitIndex = 0;
  while (amount >= 1024 && unitIndex < units.length - 1) {
    amount /= 1024;
    unitIndex++;
  }
  final decimals = amount >= 10 || unitIndex == 0 ? 0 : 1;
  return '${amount.toStringAsFixed(decimals)} ${units[unitIndex]}';
}
