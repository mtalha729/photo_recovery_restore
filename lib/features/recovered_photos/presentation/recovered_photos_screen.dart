import 'package:flutter/material.dart';

import '../../../app/design_system/components/app_components.dart';
import '../../../app/design_system/foundations/app_tokens.dart';
import '../../recovery_scan/presentation/recovery_thumbnail.dart';
import '../application/recovered_photos_store.dart';

class RecoveredPhotosScreen extends StatefulWidget {
  const RecoveredPhotosScreen({required this.store, super.key});
  final RecoveredPhotosStore store;

  @override
  State<RecoveredPhotosScreen> createState() => _RecoveredPhotosScreenState();
}

class _RecoveredPhotosScreenState extends State<RecoveredPhotosScreen> {
  late Future<List<RecoveredPhotoRecord>> _records = widget.store.load();

  Future<void> _refresh() async {
    setState(() => _records = widget.store.load());
    await _records;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recovered Photos')),
    body: FutureBuilder<List<RecoveredPhotoRecord>>(
      future: _records,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final records = snapshot.data ?? const <RecoveredPhotoRecord>[];
        if (records.isEmpty) {
          return const Center(
            child: AppEmptyState(
              icon: Icons.history_rounded,
              title: 'No restored photos yet',
              message: 'Photos you successfully restore will appear here.',
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: .78,
            ),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              return Semantics(
                label: 'Recovered photo ${record.displayName ?? 'photo'}',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(AppRadii.medium),
                          ),
                          child: RecoveryThumbnail(
                            semanticLabel: 'Recovered ${record.displayName ?? 'photo'}',
                            requestedDimension: 256,
                            contentUri: record.contentUri,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Text(
                          record.displayName ?? 'Restored photo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    ),
  );
}