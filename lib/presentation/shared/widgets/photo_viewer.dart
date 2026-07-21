import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:enpix/core/theme/context_ext.dart';
import 'package:enpix/core/theme/app_spacing.dart';

/// Full-resolution image loader with fallback.
class FullResImage extends StatefulWidget {
  final AssetEntity asset;
  const FullResImage({super.key, required this.asset});
  @override
  State<FullResImage> createState() => _FullResImageState();
}

class _FullResImageState extends State<FullResImage> {
  Uint8List? _data;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final file = await widget.asset.originFile;
      if (file != null && file.existsSync()) {
        _data = await file.readAsBytes();
      } else {
        _data = await widget.asset.thumbnailDataWithSize(
          const ThumbnailSize(2048, 2048), format: ThumbnailFormat.jpeg);
      }
    } catch (_) {
      _data = await widget.asset.thumbnailDataWithSize(
        const ThumbnailSize(1024, 1024), format: ThumbnailFormat.jpeg);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Colors.white54));
    if (_data != null) return Image.memory(_data!, fit: BoxFit.contain);
    return const Icon(Icons.broken_image_outlined, size: 48, color: Colors.white38);
  }
}

/// Immersive photo viewer with overlay controls and EXIF info.
class PhotoViewer extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;
  const PhotoViewer({super.key, required this.assets, required this.initialIndex});
  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late PageController _pageCtrl;
  late int _currentIndex;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() { _pageCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageCtrl, itemCount: widget.assets.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (context, index) => InteractiveViewer(
                minScale: 0.5, maxScale: 5.0,
                child: Center(child: FullResImage(asset: widget.assets[index])),
              ),
            ),
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: AppDuration.normal,
              child: Positioned(
                top: 0, left: 0, right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                          onPressed: () => Navigator.pop(context)),
                        Text('${_currentIndex + 1} / ${widget.assets.length}',
                            style: const TextStyle(color: Colors.white70, fontSize: 15)),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.info_outline_rounded, color: Colors.white70),
                          onPressed: () => _showInfo(context)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfo(BuildContext context) {
    final asset = widget.assets[_currentIndex];
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.backgroundSecondary.withAlpha(240),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Text('信息', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: context.colors.labelPrimary)),
            const SizedBox(height: AppSpacing.lg),
            _infoRow('类型', asset.type == AssetType.image ? '照片' : '视频'),
            _infoRow('拍摄时间', '${asset.createDateTime.year}-${asset.createDateTime.month.toString().padLeft(2, '0')}-${asset.createDateTime.day.toString().padLeft(2, '0')}'),
            _infoRow('宽', '${asset.width} px'),
            _infoRow('高', '${asset.height} px'),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(children: [
      SizedBox(width: 72, child: Text(label, style:  TextStyle(fontSize: 14, color: context.colors.labelSecondary))),
      Expanded(child: Text(value, style:  TextStyle(fontSize: 14, color: context.colors.labelPrimary))),
    ]),
  );
}
