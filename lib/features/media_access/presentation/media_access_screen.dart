import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_tokens.dart';
import '../media_access.dart';

class MediaAccessScreen extends StatefulWidget {
  const MediaAccessScreen({
    required this.coordinator,
    required this.initialState,
    required this.onAccessAvailable,
    super.key,
  });
  final MediaAccessCoordinator coordinator;
  final MediaAccessState initialState;
  final ValueChanged<MediaAccessState> onAccessAvailable;

  @override
  State<MediaAccessScreen> createState() => _MediaAccessScreenState();
}

class _MediaAccessScreenState extends State<MediaAccessScreen> {
  late MediaAccessState _state = widget.initialState;
  bool _requesting = false;
  bool _hasRequested = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Photo access')),
    body: SafeArea(
      child: ResponsiveContent(
        child: SingleChildScrollView(
          child: PremiumSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  _state.isLimited
                      ? Icons.photo_library_outlined
                      : Icons.lock_open_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(_title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Text(_message),
                const SizedBox(height: AppSpacing.lg),
                if (_state.isLimited) ...[
                  AppPrimaryButton(
                    label: 'Continue with limited access',
                    onPressed: () => widget.onAccessAvailable(_state),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppSecondaryButton(
                    label: 'Choose or change allowed photos',
                    onPressed: () => _request(
                      MediaAccessRequestIntent.changeSelectedPhotos,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _requesting
                        ? null
                        : () => _request(MediaAccessRequestIntent.fullAccess),
                    child: const Text('Request full photo access'),
                  ),
                ] else if (_state.status ==
                    MediaAccessStatus.settingsRequired) ...[
                  AppPrimaryButton(
                    label: 'Open Settings',
                    onPressed: widget.coordinator.openSettings,
                  ),
                ] else if (_state.status == MediaAccessStatus.unsupported ||
                    _state.status == MediaAccessStatus.unknown) ...[
                  Text(
                    'This device cannot provide a supported photo-access flow. No access was requested.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else ...[
                  AppPrimaryButton(
                    label: _requesting
                        ? 'Requesting…'
                        : _hasRequested &&
                              _state.status == MediaAccessStatus.denied
                        ? 'Try again'
                        : 'Continue',
                    onPressed: _requesting
                        ? null
                        : () => _request(MediaAccessRequestIntent.initial),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  String get _title => switch (_state.status) {
    MediaAccessStatus.limitedSelectedAccess => 'Limited photo access',
    MediaAccessStatus.settingsRequired => 'Allow access in Settings',
    MediaAccessStatus.denied => 'Photo access was not granted',
    MediaAccessStatus.unsupported ||
    MediaAccessStatus.unknown => 'Photo access unavailable',
    _ => 'Allow photo access',
  };

  String get _message => _state.isLimited
      ? 'Recovery can scan only the photos Android currently allows this app to access. This is not a full-library scan.'
      : 'Photo access lets recovery compare current media with verified deleted candidates, so existing photos are excluded. Processing stays on this device.';

  Future<void> _request(MediaAccessRequestIntent intent) async {
    setState(() => _requesting = true);
    final state = await widget.coordinator.requestAccess(intent: intent);
    if (!mounted) return;
    setState(() {
      _state = state;
      _requesting = false;
      _hasRequested = true;
    });
    if (state.canReadImages && !state.isLimited) {
      widget.onAccessAvailable(state);
    }
  }
}
