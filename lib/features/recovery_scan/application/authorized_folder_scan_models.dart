import '../../recovery/domain/media_candidate.dart';

enum AuthorizedFolderScanStatus {
  completed,
  selectionCancelled,
  accessRequired,
  permissionGrantLost,
  unsupported,
  cancelled,
  partialFailure,
}

class AuthorizedFolderScanProgress {
  const AuthorizedFolderScanProgress({
    required this.pageCandidates,
    required this.filesExamined,
    required this.pageCount,
    required this.entriesExamined,
  });

  final List<MediaCandidate> pageCandidates;
  final int filesExamined;
  final int pageCount;
  final int entriesExamined;
}

class AuthorizedFolderScanOutcome {
  const AuthorizedFolderScanOutcome({
    required this.status,
    this.filesExamined = 0,
    this.pageCount = 0,
    this.candidatesFound = 0,
    this.message,
  });

  final AuthorizedFolderScanStatus status;
  final int filesExamined;
  final int pageCount;
  final int candidatesFound;
  final String? message;
}
