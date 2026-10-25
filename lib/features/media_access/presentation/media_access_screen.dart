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
  void initState() {
    super.initState();
    // Recover Photos was an explicit user action, so open Android's runtime
    // permission dialog without requiring another redundant tap in this UI.
    if (_state.status == MediaAccessStatus.denied) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _request(MediaAccessRequestIntent.fullAccess);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Storage Access')),
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
                    label: 'Grant Access',
                    onPressed: _requesting
                        ? null
                        : () => _request(MediaAccessRequestIntent.fullAccess),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppSecondaryButton(
                    label: 'Continue with selected photos',
                    onPressed: () => widget.onAccessAvailable(_state),
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
                        : 'Grant Access',
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
    MediaAccessStatus.limitedSelectedAccess => 'Selected photos only',
    MediaAccessStatus.settingsRequired => 'Allow storage access in Settings',
    MediaAccessStatus.denied => 'Storage access was not granted',
    MediaAccessStatus.unsupported ||
    MediaAccessStatus.unknown => 'Photo access unavailable',
    _ => 'Storage Access',
  };

  String get _message => _state.isLimited
      ? 'Android granted access to selected photos only. Request full photo access to scan the complete photo library; this app cannot change that choice without your approval.'
      : 'Allow access to photos and available device storage so Photo Recovery & Restore can search for recoverable images.';

  Future<void> _request(MediaAccessRequestIntent intent) async {
    setState(() => _requesting = true);
    final state = await widget.coordinator.requestAccess(intent: intent);
    if (!mounted) return;
    setState(() {
      _state = state;
      _requesting = false;
      _hasRequested = true;
    });
    if (state.canReadImages) {
      widget.onAccessAvailable(state);
    }
  }
}
