import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:enpix/core/theme/app_spacing.dart';
import 'package:enpix/presentation/shared/utils/format_duration.dart';

/// Full-screen video player for a local [AssetEntity] video.
///
/// Initializes from `asset.originFile`, loops by default, with play/pause,
/// a seek slider, and `mm:ss` position / duration. Falls back to a broken
/// state if the file cannot be loaded.
class VideoPlayerPage extends StatefulWidget {
  final AssetEntity asset;

  const VideoPlayerPage({super.key, required this.asset});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _error = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final file = await widget.asset.originFile;
      if (file == null) {
        if (mounted) setState(() => _error = true);
        return;
      }
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      unawaited(controller.setLooping(true));
      controller.addListener(_onChanged);
      _controller = controller;
      if (mounted) {
        setState(() => _initialized = true);
        unawaited(controller.play());
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Stack(
          children: [
            Center(child: _buildContent()),
            if (_showControls && _initialized) _buildControls(context),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_error) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 48, color: Colors.white54),
          SizedBox(height: AppSpacing.sm),
          Text('无法播放视频', style: TextStyle(color: Colors.white70)),
        ],
      );
    }
    if (!_initialized) {
      return const CircularProgressIndicator(color: Colors.white54);
    }
    final c = _controller!;
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: SizedBox(
        width: MediaQuery.of(context).size.width,
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 1.0 : c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final c = _controller!;
    final pos = c.value.position;
    final dur = c.value.duration;
    final durSecs = dur.inSeconds < 1 ? 1 : dur.inSeconds;

    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: '关闭',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const Spacer(),
          Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    c.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (c.value.isPlaying) {
                      c.pause();
                    } else {
                      c.play();
                    }
                  },
                ),
                Expanded(
                  child: Slider(
                    value:
                        pos.inSeconds.toDouble().clamp(0, durSecs.toDouble()),
                    min: 0,
                    max: durSecs.toDouble(),
                    onChanged: (v) => c.seekTo(Duration(seconds: v.toInt())),
                  ),
                ),
                Text(
                  '${formatDuration(pos.inSeconds)} / ${formatDuration(dur.inSeconds)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
