import 'package:flutter_test/flutter_test.dart';
import 'package:photo_recovery_restore/features/recovery/application/existing_media_exclusion/existing_media_index.dart';
import 'package:photo_recovery_restore/features/recovery/application/source_recovery/verified_source_recovery_pipeline.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery.dart';
import 'package:photo_recovery_restore/features/recovery/data/trash_discovery/trash_discovery_models.dart';
import 'package:photo_recovery_restore/features/recovery/domain/deletion_evidence.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_candidate.dart';
import 'package:photo_recovery_restore/features/recovery/domain/media_source.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_classification.dart';
import 'package:photo_recovery_restore/features/recovery/domain/recovery_quality.dart';
import 'package:photo_recovery_restore/features/recovery/domain/restore_capability.dart';

void main() {
  test('all-photo verified trash keeps Unknown and SD source identities', () {
    final pipeline = VerifiedSourceRecoveryPipeline(
      trashDiscovery: const _UnusedTrashDiscovery(),
    );
    final result = pipeline.processCandidates(
      source: MediaSource.unknown,
      candidates: [
        _candidate('unknown', MediaSource.unknown),
        _candidate('sd', MediaSource.sdCard),
      ],
      existingMediaIndex: ExistingMediaIndex.build(records: const []),
      androidApiLevel: 34,
    );

    expect(result.items.map((item) => item.candidate.source), [
      MediaSource.unknown,
      MediaSource.sdCard,
    ]);
    expect(result.diagnostics.filteredOtherSourceCount, 0);
  });
}

MediaCandidate _candidate(String id, MediaSource source) => MediaCandidate(
  id: id,
  source: source,
  classification: RecoveryClassification.unclassified,
  deletionEvidence: DeletionEvidence(
    reasons: const [DeletionEvidenceReason.systemTrashRecord],
  ),
  restoreCapability: RestoreCapability.originalFullQuality,
  recoveryQuality: RecoveryQuality.original,
);

class _UnusedTrashDiscovery implements TrashDiscovery {
  const _UnusedTrashDiscovery();

  @override
  Future<TrashDiscoveryResult> getVerifiedTrashPage(
    TrashDiscoveryPageRequest request,
  ) => throw UnimplementedError();
}
