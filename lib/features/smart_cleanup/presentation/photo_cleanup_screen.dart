import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_tokens.dart';
import '../../recovery_scan/presentation/recovery_thumbnail.dart';
import '../application/photo_cleanup_engine.dart';
import '../application/photo_cleanup_models.dart';

class PhotoCleanupScreen extends StatefulWidget {
  const PhotoCleanupScreen({
    required this.category,
    required this.engine,
    required this.deletionExecutor,
    super.key,
  });

  final PhotoCleanupCategory category;
  final PhotoCleanupEngine engine;
  final PhotoCleanupDeletionExecutor deletionExecutor;

  @override
  State<PhotoCleanupScreen> createState() => _PhotoCleanupScreenState();
}

class _PhotoCleanupScreenState extends State<PhotoCleanupScreen> {
  final _selection = PhotoCleanupSelection();
  PhotoCleanupIndex? _index;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final index = await widget.engine.load(category: widget.category);
      if (mounted) {
        setState(() {
          _index = index;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  String get _title => switch (widget.category) {
    PhotoCleanupCategory.duplicatePhotos => 'Duplicate Photos',
    PhotoCleanupCategory.oldPhotos => 'Old Photos',
    PhotoCleanupCategory.largePhotos => 'Large Photos',
  };

  String get _emptyMessage => switch (widget.category) {
    PhotoCleanupCategory.duplicatePhotos => 'No duplicate photos found',
    PhotoCleanupCategory.oldPhotos => 'No old photos found',
    PhotoCleanupCategory.largePhotos => 'No large photos found',
  };

  List<CleanupPhoto> _photos(PhotoCleanupIndex index) =>
      switch (widget.category) {
        PhotoCleanupCategory.duplicatePhotos =>
          index.duplicateGroups.expand((group) => group.photos).toList(),
        PhotoCleanupCategory.oldPhotos => index.oldPhotos,
        PhotoCleanupCategory.largePhotos => index.largePhotos,
      };

  Set<String> _protected(PhotoCleanupIndex index) =>
      widget.category == PhotoCleanupCategory.duplicatePhotos
      ? index.duplicateGroups.map((group) => group.protectedPhoto.id).toSet()
      : const {};

  Future<void> _delete() async {
    final visible = _index == null ? const <CleanupPhoto>[] : _photos(_index!);
    if (!_selection.canDelete || visible.isEmpty) return;
    setState(_selection.beginDeletion);
    try {
      final outcome = await widget.engine.deleteSelected(
        _selection.selectedIds,
        widget.deletionExecutor,
      );
      final updated = await widget.engine.load(category: widget.category);
      if (!mounted) {
        return;
      }
      _selection.removeAll(outcome.deletedIds);
      setState(() => _index = updated);
      final message = outcome.cancelled
          ? 'Deletion cancelled'
          : outcome.deletedIds.isEmpty
          ? 'No photos were deleted'
          : '${outcome.deletedIds.length} ${outcome.deletedIds.length == 1 ? 'photo' : 'photos'} deleted';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to delete the selected photos')),
        );
      }
    } finally {
      if (mounted) {
        setState(_selection.endDeletion);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? AppEmptyState(
              icon: Icons.photo_library_outlined,
              title: 'Photo access is unavailable',
              message: 'Allow photo access, then try again.',
              action: AppPrimaryButton(label: 'Try again', onPressed: _load),
            )
          : index == null || _photos(index).isEmpty
          ? AppEmptyState(
              icon: Icons.photo_library_outlined,
              title: _emptyMessage,
              message: 'Your current photos are kept separate from recovery results.',
            )
          : _content(context, index),
      bottomNavigationBar: index == null ? null : _bottomAction(context, index),
    );
  }

  Widget _content(BuildContext context, PhotoCleanupIndex index) {
    final photos = _photos(index);
    final protected = _protected(index);
    final total = photos.fold<int>(0, (value, photo) => value + photo.byteSize);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${photos.length} photos • ${_formatBytes(total)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: () => setState(
                  () => _selection.selectAll(photos, protectedIds: protected),
                ),
                child: const Text('Select all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              100,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: .82,
            ),
            itemCount: photos.length,
            itemBuilder: (context, i) {
              final photo = photos[i];
              final isProtected = protected.contains(photo.id);
              final selected = _selection.selectedIds.contains(photo.id);
              return Semantics(
                button: !isProtected,
                selected: selected,
                label: isProtected
                    ? '${photo.record.displayName ?? 'Photo'}, protected best copy'
                    : photo.record.displayName ?? 'Photo',
                child: Material(
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(AppRadii.large),
                  child: InkWell(
                    onTap: isProtected
                        ? null
                        : () => setState(
                            () => _selection.toggle(
                              photo,
                              protectedIds: protected,
                            ),
                          ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: RecoveryThumbnail(
                            semanticLabel: photo.record.displayName ?? 'Photo',
                            contentUri: photo.record.contentUri,
                            requestedDimension: 256,
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Icon(
                            selected
                                ? Icons.check_circle
                                : isProtected
                                ? Icons.shield_rounded
                                : Icons.radio_button_unchecked,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white,
                          ),
                        ),
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 6,
                          child: Text(
                            isProtected
                                ? 'Protected best copy'
                                : _formatBytes(photo.byteSize),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  shadows: const [Shadow(blurRadius: 4)],
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _bottomAction(BuildContext context, PhotoCleanupIndex index) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: AppPrimaryButton(
          label: _selection.isDeleting
              ? 'Deleting…'
              : 'Delete selected${_selection.selectedIds.isEmpty ? '' : ' (${_selection.selectedIds.length})'}',
          icon: Icons.delete_outline_rounded,
          onPressed: _selection.canDelete ? _delete : null,
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(value >= 10 || index == 0 ? 0 : 1)} ${units[index]}';
}
