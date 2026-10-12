import '../../data/current_media_inventory/current_media_inventory_models.dart';
import '../../data/media_metadata/current_media_metadata.dart';

class ExistingMediaReference {
  const ExistingMediaReference({required this.record, this.metadata});

  final CurrentMediaRecord record;
  final CurrentMediaMetadata? metadata;
}

enum ExistingMediaDecisionType {
  definitelyExisting,
  noExistingMatch,
  uncertainIdentity,
}

class ExistingMediaDecision {
  const ExistingMediaDecision._({required this.type, this.match});

  const ExistingMediaDecision.definitelyExisting(ExistingMediaReference match)
    : this._(type: ExistingMediaDecisionType.definitelyExisting, match: match);

  const ExistingMediaDecision.noExistingMatch()
    : this._(type: ExistingMediaDecisionType.noExistingMatch);

  const ExistingMediaDecision.uncertainIdentity()
    : this._(type: ExistingMediaDecisionType.uncertainIdentity);

  final ExistingMediaDecisionType type;
  final ExistingMediaReference? match;

  bool get excludesFromDeletedResults =>
      type == ExistingMediaDecisionType.definitelyExisting;
}
