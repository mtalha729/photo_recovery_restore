import 'package:flutter/services.dart';

import '../../recovery/domain/media_candidate.dart';

class RecoveredPhotoRecord {
  const RecoveredPhotoRecord({
    required this.id,
    required this.contentUri,
    required this.restoredAt,
    this.displayName,
    this.mimeType,
    this.source,
  });

  final String id;
  final Uri contentUri;
  final DateTime restoredAt;
  final String? displayName;
  final String? mimeType;
  final String? source;

  factory RecoveredPhotoRecord.fromCandidate({
    required Uri contentUri,
    required MediaCandidate candidate,
    required DateTime restoredAt,
  }) => RecoveredPhotoRecord(
    id: contentUri.toString(),
    contentUri: contentUri,
    restoredAt: restoredAt,
    displayName: candidate.displayName,
    mimeType: candidate.mimeType,
    source: candidate.source.name,
  );

  factory RecoveredPhotoRecord.fromMap(Map<Object?, Object?> raw) {
    final uri = raw['contentUri'];
    final restoredAt = raw['restoredAtMillis'];
    if (uri is! String || restoredAt is! int) {
      throw const FormatException('Invalid recovered-photo history record.');
    }
    final parsed = Uri.tryParse(uri);
    if (parsed == null || parsed.scheme != 'content') {
      throw const FormatException('Recovered-photo history needs a content URI.');
    }
    return RecoveredPhotoRecord(
      id: raw['id'] is String ? raw['id']! as String : uri,
      contentUri: parsed,
      restoredAt: DateTime.fromMillisecondsSinceEpoch(restoredAt),
      displayName: raw['displayName'] as String?,
      mimeType: raw['mimeType'] as String?,
      source: raw['source'] as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'contentUri': contentUri.toString(),
    'restoredAtMillis': restoredAt.millisecondsSinceEpoch,
    'displayName': displayName,
    'mimeType': mimeType,
    'source': source,
  };
}

abstract interface class RecoveredPhotosStore {
  Future<List<RecoveredPhotoRecord>> load();
  Future<void> upsert(RecoveredPhotoRecord record);
}

class PlatformRecoveredPhotosStore implements RecoveredPhotosStore {
  PlatformRecoveredPhotosStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.photorecoveryrestore.app/recovered_photos';
  final MethodChannel _channel;

  @override
  Future<List<RecoveredPhotoRecord>> load() async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('loadHistory') ?? const [];
      final records = <RecoveredPhotoRecord>[];
      for (final value in raw) {
        if (value is! Map<Object?, Object?>) continue;
        try {
          records.add(RecoveredPhotoRecord.fromMap(value));
        } on FormatException {
          // Ignore a malformed/stale local row rather than breaking history.
        }
      }
      records.sort((a, b) => b.restoredAt.compareTo(a.restoredAt));
      return List.unmodifiable(records);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<void> upsert(RecoveredPhotoRecord record) async {
    try {
      await _channel.invokeMethod<void>('upsertHistory', record.toMap());
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}