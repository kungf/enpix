import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/presentation/shared/widgets/enpix_skeleton.dart';
import 'package:enpix/services/cloud/cloud_media.dart';
import 'package:enpix/services/cloud/cloud_providers.dart';
import 'package:enpix/services/thumbnail/thumbnail_loader.dart';

/// One encrypted cloud photo in the 3-column grid.
///
/// Loads its thumbnail through the shared in-memory LRU; a failed fetch
/// shows a retry affordance instead of a dead tile.
class CloudThumbTile extends ConsumerStatefulWidget {
  const CloudThumbTile({
    super.key,
    required this.media,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  final CloudMedia media;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  ConsumerState<CloudThumbTile> createState() => _CloudThumbTileState();
}

class _CloudThumbTileState extends ConsumerState<CloudThumbTile> {
  static final Logger _log = Logger('CloudThumbTile');

  Uint8List? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ref.read(cloudThumbnailLoaderProvider).load(
          widget.media.thumbnailKey,
          _fetch,
        );
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<Uint8List?> _fetch() async {
    try {
      return await ref
          .read(cloudMediaRepositoryProvider)
          .loadThumbnail(widget.media);
    } on Exception catch (e) {
      _log.warning('Thumbnail load failed: ${widget.media.thumbnailKey} — $e');
      return null;
    }
  }

  void _retry() {
    setState(() => _loading = true);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final failed = !_loading && _data == null;
    return GestureDetector(
      onTap: _loading ? null : (failed ? _retry : widget.onTap),
      onLongPress: widget.onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildImage(context),
          if (widget.isSelectionMode)
            _buildSelectionOverlay(context)
          else
            _buildLockBadge(context),
        ],
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xxs),
      child: _loading
          ? const EnpixSkeleton(width: 200, height: 200)
          : _data != null
              ? Image.memory(_data!, fit: BoxFit.cover)
              : Container(
                  color: context.colors.fillSecondary,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: context.colors.brandGray,
                    size: 32,
                  ),
                ),
    );
  }

  Widget _buildLockBadge(BuildContext context) {
    return Positioned(
      top: AppSpacing.xs,
      right: AppSpacing.xs,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: context.colors.brandPurple.withAlpha(180),
          borderRadius: BorderRadius.circular(AppRadius.xxs),
        ),
        child: const Icon(Icons.lock_rounded, size: 12, color: Colors.white),
      ),
    );
  }

  Widget _buildSelectionOverlay(BuildContext context) {
    final selected = widget.isSelected;
    return Container(
      decoration: BoxDecoration(
        color: selected ? Colors.black38 : Colors.transparent,
        border: selected
            ? Border.all(color: context.colors.brandBlue, width: 3)
            : null,
        borderRadius: BorderRadius.circular(AppRadius.xxs),
      ),
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 22,
            color: selected ? context.colors.brandBlue : Colors.white,
          ),
        ),
      ),
    );
  }
}
