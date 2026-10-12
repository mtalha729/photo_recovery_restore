import 'package:flutter/material.dart';

import '../../recovery/application/scan_runtime/recovery_image_memory_policy.dart';
import '../../thumbnails/bounded_thumbnail_provider.dart';

class RecoveryThumbnail extends StatefulWidget {
  const RecoveryThumbnail({
    required this.semanticLabel,
    this.requestedDimension = 256,
    this.contentUri,
    this.filePath,
    this.provider,
    this.fit = BoxFit.cover,
    super.key,
  }) : assert(requestedDimension > 0),
       assert(
         requestedDimension <=
             RecoveryImageMemoryPolicy.maximumThumbnailDimension,
       );

  final String semanticLabel;
  final int requestedDimension;
  final Uri? contentUri;
  final String? filePath;
  final BoundedThumbnailProvider? provider;
  final BoxFit fit;

  @override
  State<RecoveryThumbnail> createState() => _RecoveryThumbnailState();
}

class _RecoveryThumbnailState extends State<RecoveryThumbnail> {
  Future<ThumbnailResult>? _pending;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RecoveryThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentUri != widget.contentUri ||
        oldWidget.filePath != widget.filePath ||
        oldWidget.requestedDimension != widget.requestedDimension) {
      _load();
    }
  }

  void _load() {
    final uri = widget.contentUri;
    final provider = widget.provider ?? PlatformBoundedThumbnailProvider();
    _pending = uri != null
        ? provider.load(
            uri,
            width: widget.requestedDimension,
            height: widget.requestedDimension,
          )
        : widget.filePath == null
        ? null
        : provider.loadFile(
            widget.filePath!,
            width: widget.requestedDimension,
            height: widget.requestedDimension,
          );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: widget.semanticLabel,
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: _pending == null
          ? _placeholder(context)
          : FutureBuilder<ThumbnailResult>(
              future: _pending,
              builder: (context, snapshot) {
                final bytes = snapshot.data?.bytes;
                return bytes == null
                    ? _placeholder(context)
                    : Image.memory(
                        bytes,
                        fit: widget.fit,
                        cacheWidth: widget.requestedDimension,
                        cacheHeight: widget.requestedDimension,
                        errorBuilder: (_, _, _) => _placeholder(context),
                      );
              },
            ),
    ),
  );

  Widget _placeholder(BuildContext context) => Center(
    child: Icon(
      Icons.image_outlined,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}
