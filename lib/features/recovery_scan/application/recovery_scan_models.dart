import '../../recovery/application/scan_runtime/paginated_recovery_scanner.dart';
import '../../recovery/domain/media_candidate.dart';
import '../../recovery/domain/media_source.dart';

enum RecoveryScanSource {
  allPhotos(MediaSource.unknown, 'Recover Photos'),
  cameraGallery(MediaSource.cameraGallery, 'Camera & Gallery'),
  messaging(MediaSource.messagingSharedMedia, 'Messaging'),
  screenshots(MediaSource.screenshots, 'Screenshots'),
  downloads(MediaSource.downloadsSavedMedia, 'Downloads'),
  sdCard(MediaSource.sdCard, 'SD Card & Other Folders'),
  customFolder(MediaSource.customFolder, 'Selected Folder');

  const RecoveryScanSource(this.mediaSource, this.label);
  final MediaSource mediaSource;
  final String label;
}

enum RecoveryScanViewStatus {
  idle,
  running,
  cancelling,
  cancelled,
  complete,
  empty,
  unsupported,
  accessUnavailable,
  deepAccessRequired,
  failure,
}

class RecoveryScanViewState {
  const RecoveryScanViewState({
    required this.source,
    this.status = RecoveryScanViewStatus.idle,
    this.progress = const RecoveryScanProgress(
      processedCount: 0,
      pageCount: 0,
      discoveredVerifiedCount: 0,
    ),
    this.verifiedItems = const [],
    this.possibleCopies = const [],
    this.message,
    this.isLimitedAccess = false,
    this.deepCapabilityMessage,
    this.deepDirectoriesExamined = 0,
    this.deepCandidatesFound = 0,
    this.currentScanArea,
    this.scanPhase = 'MediaStore',
  });

  final RecoveryScanSource source;
  final RecoveryScanViewStatus status;
  final RecoveryScanProgress progress;
  final List<MediaCandidate> verifiedItems;
  final List<MediaCandidate> possibleCopies;
  final String? message;
  final bool isLimitedAccess;
  final String? deepCapabilityMessage;
  final int deepDirectoriesExamined;
  final int deepCandidatesFound;
  final String? currentScanArea;
  final String scanPhase;

  RecoveryScanViewState copyWith({
    RecoveryScanViewStatus? status,
    RecoveryScanProgress? progress,
    List<MediaCandidate>? verifiedItems,
    List<MediaCandidate>? possibleCopies,
    String? message,
    bool? isLimitedAccess,
    String? deepCapabilityMessage,
    int? deepDirectoriesExamined,
    int? deepCandidatesFound,
    String? currentScanArea,
    String? scanPhase,
  }) => RecoveryScanViewState(
    source: source,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    verifiedItems: verifiedItems ?? this.verifiedItems,
    possibleCopies: possibleCopies ?? this.possibleCopies,
    message: message ?? this.message,
    isLimitedAccess: isLimitedAccess ?? this.isLimitedAccess,
    deepCapabilityMessage: deepCapabilityMessage ?? this.deepCapabilityMessage,
    deepDirectoriesExamined:
        deepDirectoriesExamined ?? this.deepDirectoriesExamined,
    deepCandidatesFound: deepCandidatesFound ?? this.deepCandidatesFound,
    currentScanArea: currentScanArea ?? this.currentScanArea,
    scanPhase: scanPhase ?? this.scanPhase,
  );
}
