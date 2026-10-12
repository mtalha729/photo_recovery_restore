import '../../data/media_metadata/current_media_metadata.dart';
import '../../domain/media_source.dart';

enum MessagingProvider { whatsApp, telegram, other }

class MediaSourceResolution {
  const MediaSourceResolution({required this.source, this.messagingProvider});

  final MediaSource source;
  final MessagingProvider? messagingProvider;
}

class MediaSourceResolver {
  const MediaSourceResolver();

  MediaSource resolve(CurrentMediaMetadata metadata) =>
      resolveDetails(metadata).source;

  MediaSourceResolution resolveDetails(CurrentMediaMetadata metadata) {
    final path = _normalized(metadata.relativePath);
    final bucket = _normalized(metadata.bucketName);
    final location = [path, bucket].whereType<String>().join('/');

    if (path == 'android/data' || path?.startsWith('android/data/') == true) {
      return const MediaSourceResolution(source: MediaSource.unknown);
    }
    if (_containsSegment(location, const {'screenshots', 'screenshot'})) {
      return const MediaSourceResolution(source: MediaSource.screenshots);
    }
    final messagingProvider = _messagingProvider(location);
    if (messagingProvider != null) {
      return MediaSourceResolution(
        source: MediaSource.messagingSharedMedia,
        messagingProvider: messagingProvider,
      );
    }
    if (_containsSegment(location, const {'download', 'downloads'})) {
      return const MediaSourceResolution(
        source: MediaSource.downloadsSavedMedia,
      );
    }
    if (metadata.isRemovableStorage == true) {
      return const MediaSourceResolution(source: MediaSource.sdCard);
    }
    if (path != null &&
        (path == 'dcim' ||
            path.startsWith('dcim/') ||
            path == 'pictures' ||
            path.startsWith('pictures/'))) {
      return const MediaSourceResolution(source: MediaSource.cameraGallery);
    }
    if (bucket == 'camera' || bucket == 'gallery' || bucket == 'pictures') {
      return const MediaSourceResolution(source: MediaSource.cameraGallery);
    }
    return const MediaSourceResolution(source: MediaSource.unknown);
  }

  MessagingProvider? _messagingProvider(String location) {
    if (_containsSegment(location, const {
      'whatsapp',
      'whatsapp images',
      'com.whatsapp',
    })) {
      return MessagingProvider.whatsApp;
    }
    if (_containsSegment(location, const {
      'telegram',
      'telegram images',
      'org.telegram.messenger',
    })) {
      return MessagingProvider.telegram;
    }
    if (_containsSegment(location, const {'signal', 'messenger', 'viber'})) {
      return MessagingProvider.other;
    }
    return null;
  }

  bool _containsSegment(String value, Set<String> categories) {
    final segments = value.split('/').where((segment) => segment.isNotEmpty);
    return segments.any(categories.contains);
  }

  String? _normalized(String? value) {
    final normalized = value
        ?.trim()
        .replaceAll('\\', '/')
        .replaceAll(RegExp('/+'), '/')
        .replaceAll(RegExp(r'^/+|/+$'), '')
        .toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
