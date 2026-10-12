import '../../data/current_media_inventory/current_media_inventory_models.dart';
import '../../data/media_metadata/current_media_metadata.dart';
import 'existing_media_exclusion_models.dart';

class ExistingMediaIndex {
  ExistingMediaIndex._({
    required this._byUri,
    required this._byPlatformIdentity,
    required this._byStorageLocation,
    required this._byCompositeMetadata,
    required this._fileNames,
    required this._dimensions,
    required this._timestamps,
    required this.indexedRecordCount,
  });

  factory ExistingMediaIndex.build({
    required Iterable<CurrentMediaRecord> records,
    Iterable<CurrentMediaMetadata> metadata = const [],
  }) {
    final recordList = records.toList(growable: false);
    final combinedMetadata = <CurrentMediaMetadata>[
      ...metadata,
      ...recordList.map(_metadataFromInventoryRecord),
    ];
    final metadataByUri = <String, CurrentMediaMetadata>{};
    final metadataByPlatformIdentity = <String, CurrentMediaMetadata>{};
    final metadataById = <int, List<CurrentMediaMetadata>>{};
    for (final value in combinedMetadata) {
      (metadataById[value.mediaStoreId] ??= []).add(value);
      final uriKey = ExistingMediaKeys.uri(value.contentUri);
      if (uriKey != null) metadataByUri[uriKey] = value;
      final platformKey = ExistingMediaKeys.platformIdentity(
        mediaStoreId: value.mediaStoreId,
        storageVolumeName: value.storageVolumeName,
      );
      if (platformKey != null) metadataByPlatformIdentity[platformKey] = value;
    }
    final uniqueReferences = <String, ExistingMediaReference>{};

    for (final record in recordList) {
      final normalizedUri = ExistingMediaKeys.uri(record.contentUri);
      final platformKey = ExistingMediaKeys.platformIdentity(
        mediaStoreId: record.mediaStoreId,
        storageVolumeName: record.storageVolumeName,
      );
      final key =
          normalizedUri ?? platformKey ?? 'id:unknown:${record.mediaStoreId}';
      uniqueReferences.putIfAbsent(
        key,
        () => ExistingMediaReference(
          record: record,
          // Prefer the most complete metadata among every record sharing this
          // MediaStore id. A batched lightweight record can share its URI with
          // an enriched record, so selecting the URI map entry first loses
          // paths, sizes, and volume identity needed for safe exclusion.
          metadata: _bestMetadataForRecord(
            record,
            metadataById[record.mediaStoreId] ?? const [],
          ),
        ),
      );
    }

    final byUri = <String, List<ExistingMediaReference>>{};
    final byPlatformIdentity = <String, List<ExistingMediaReference>>{};
    final byStorageLocation = <String, List<ExistingMediaReference>>{};
    final byCompositeMetadata = <String, List<ExistingMediaReference>>{};
    final fileNames = <String>{};
    final dimensions = <String>{};
    final timestamps = <int>{};

    for (final reference in uniqueReferences.values) {
      final record = reference.record;
      final metadataValue = reference.metadata;
      _add(byUri, ExistingMediaKeys.uri(record.contentUri), reference);
      _add(
        byPlatformIdentity,
        ExistingMediaKeys.platformIdentity(
          mediaStoreId: record.mediaStoreId,
          storageVolumeName:
              metadataValue?.storageVolumeName ?? record.storageVolumeName,
        ),
        reference,
      );
      _add(
        byStorageLocation,
        ExistingMediaKeys.storageLocation(
          storageVolumeName:
              metadataValue?.storageVolumeName ?? record.storageVolumeName,
          relativeLocation: metadataValue?.relativePath,
          displayName: metadataValue?.displayName ?? record.displayName,
          byteSize: metadataValue?.byteSize,
        ),
        reference,
      );
      _add(
        byCompositeMetadata,
        ExistingMediaKeys.compositeMetadata(
          displayName: metadataValue?.displayName ?? record.displayName,
          mimeType: metadataValue?.mimeType ?? record.mimeType,
          byteSize: metadataValue?.byteSize,
          width: metadataValue?.width,
          height: metadataValue?.height,
          relativeLocation: metadataValue?.relativePath,
          bucketName: metadataValue?.bucketName,
        ),
        reference,
      );

      final fileName = ExistingMediaKeys.text(
        metadataValue?.displayName ?? record.displayName,
      );
      if (fileName != null) fileNames.add(fileName);
      final dimensionKey = ExistingMediaKeys.dimensions(
        metadataValue?.width,
        metadataValue?.height,
      );
      if (dimensionKey != null) dimensions.add(dimensionKey);
      for (final timestamp in [
        metadataValue?.dateTaken,
        metadataValue?.dateModified,
        metadataValue?.dateAdded,
      ]) {
        if (timestamp != null) timestamps.add(timestamp.millisecondsSinceEpoch);
      }
    }

    return ExistingMediaIndex._(
      byUri: byUri,
      byPlatformIdentity: byPlatformIdentity,
      byStorageLocation: byStorageLocation,
      byCompositeMetadata: byCompositeMetadata,
      fileNames: fileNames,
      dimensions: dimensions,
      timestamps: timestamps,
      indexedRecordCount: uniqueReferences.length,
    );
  }

  static CurrentMediaMetadata _metadataFromInventoryRecord(
    CurrentMediaRecord record,
  ) => CurrentMediaMetadata(
    mediaStoreId: record.mediaStoreId,
    contentUri: record.contentUri,
    displayName: record.displayName,
    mimeType: record.mimeType,
    byteSize: record.byteSize,
    width: record.width,
    height: record.height,
    dateTaken: record.dateTaken,
    dateAdded: record.dateAdded,
    dateModified: record.dateModified,
    relativePath: record.relativePath,
    bucketName: record.bucketName,
    orientationDegrees: record.orientationDegrees,
    storageVolumeName: record.storageVolumeName,
  );

  /// The batched inventory supplies a lightweight record and may also supply
  /// an enriched metadata record for the same MediaStore id.  The lightweight
  /// projection must not make the enriched entry look ambiguous.  We only
  /// select a metadata entry by id when it is uniquely the most complete;
  /// equal-strength entries can still represent different volumes and remain
  /// intentionally unresolved.
  static CurrentMediaMetadata? _bestMetadataForRecord(
    CurrentMediaRecord record,
    List<CurrentMediaMetadata> values,
  ) {
    if (values.isEmpty) return null;
    if (values.length == 1) return values.single;

    final scored =
        values
            .map(
              (value) => (value: value, score: _metadataScore(value, record)),
            )
            .toList(growable: false)
          ..sort((a, b) => b.score.compareTo(a.score));
    if (scored.length > 1 && scored.first.score == scored[1].score) {
      return null;
    }
    return scored.first.value;
  }

  static int _metadataScore(
    CurrentMediaMetadata value,
    CurrentMediaRecord record,
  ) {
    var score = 0;
    for (final present in [
      value.contentUri != null,
      ExistingMediaKeys.text(value.displayName) != null,
      ExistingMediaKeys.lowerText(value.mimeType) != null,
      value.byteSize != null,
      ExistingMediaKeys.dimensions(value.width, value.height) != null,
      value.dateTaken != null,
      value.dateAdded != null,
      value.dateModified != null,
      ExistingMediaKeys.normalizedLocation(value.relativePath) != null,
      ExistingMediaKeys.text(value.bucketName) != null,
      value.orientationDegrees != null,
      ExistingMediaKeys.lowerText(value.storageVolumeName) != null,
    ]) {
      if (present) score++;
    }
    // A URI or volume that agrees with the inventory record is stronger than
    // unrelated metadata sharing only a numeric MediaStore id.
    if (value.contentUri != null && value.contentUri == record.contentUri) {
      score += 2;
    }
    if (ExistingMediaKeys.lowerText(value.storageVolumeName) != null &&
        ExistingMediaKeys.lowerText(value.storageVolumeName) ==
            ExistingMediaKeys.lowerText(record.storageVolumeName)) {
      score += 2;
    }
    return score;
  }

  final Map<String, List<ExistingMediaReference>> _byUri;
  final Map<String, List<ExistingMediaReference>> _byPlatformIdentity;
  final Map<String, List<ExistingMediaReference>> _byStorageLocation;
  final Map<String, List<ExistingMediaReference>> _byCompositeMetadata;
  final Set<String> _fileNames;
  final Set<String> _dimensions;
  final Set<int> _timestamps;

  final int indexedRecordCount;

  List<ExistingMediaReference>? findByUri(String key) => _byUri[key];

  List<ExistingMediaReference>? findByPlatformIdentity(String key) =>
      _byPlatformIdentity[key];

  List<ExistingMediaReference>? findByStorageLocation(String key) =>
      _byStorageLocation[key];

  List<ExistingMediaReference>? findByCompositeMetadata(String key) =>
      _byCompositeMetadata[key];

  bool containsFileName(String key) => _fileNames.contains(key);

  bool containsDimensions(String key) => _dimensions.contains(key);

  bool containsTimestamp(int millisecondsSinceEpoch) =>
      _timestamps.contains(millisecondsSinceEpoch);

  /// Exact volume/location/name/size identities for inexpensive native
  /// prefiltering. Dart exclusion remains authoritative after discovery.
  Set<String> get storageLocationKeys =>
      Set.unmodifiable(_byStorageLocation.keys);

  static void _add(
    Map<String, List<ExistingMediaReference>> index,
    String? key,
    ExistingMediaReference reference,
  ) {
    if (key != null) (index[key] ??= []).add(reference);
  }
}

class ExistingMediaKeys {
  const ExistingMediaKeys._();

  static String? uri(Uri? value) {
    return text(value?.toString());
  }

  static String? platformIdentity({
    required int? mediaStoreId,
    required String? storageVolumeName,
  }) {
    final volume = lowerText(storageVolumeName);
    if (mediaStoreId == null || mediaStoreId < 0 || volume == null) return null;
    return '$volume|$mediaStoreId';
  }

  static String? compositeMetadata({
    required String? displayName,
    required String? mimeType,
    required int? byteSize,
    required int? width,
    required int? height,
    required String? relativeLocation,
    required String? bucketName,
  }) {
    final name = text(displayName);
    final mime = lowerText(mimeType);
    final location = normalizedLocation(relativeLocation) ?? text(bucketName);
    if (name == null ||
        mime == null ||
        byteSize == null ||
        byteSize < 0 ||
        width == null ||
        width <= 0 ||
        height == null ||
        height <= 0 ||
        location == null) {
      return null;
    }
    return '$name|$mime|$byteSize|${dimensions(width, height)}|$location';
  }

  static String? storageLocation({
    required String? storageVolumeName,
    required String? relativeLocation,
    required String? displayName,
    required int? byteSize,
  }) {
    final volume = lowerText(storageVolumeName);
    final location = normalizedLocation(relativeLocation);
    final name = lowerText(displayName);
    if (volume == null ||
        location == null ||
        name == null ||
        byteSize == null ||
        byteSize < 0) {
      return null;
    }
    return '$volume|$location|$name|$byteSize';
  }

  static String? dimensions(int? width, int? height) {
    if (width == null || width <= 0 || height == null || height <= 0) {
      return null;
    }
    return '${width}x$height';
  }

  static String? text(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String? lowerText(String? value) => text(value)?.toLowerCase();

  static String? normalizedLocation(String? value) {
    final normalized = text(value)
        ?.replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+'), '/')
        .replaceFirst(RegExp(r'^/+'), '')
        .replaceFirst(RegExp(r'/+$'), '');
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
