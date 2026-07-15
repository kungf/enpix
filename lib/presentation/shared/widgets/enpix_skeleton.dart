import 'package:flutter/material.dart';
import 'package:enpix/core/theme/app_colors.dart';
import 'package:enpix/core/theme/app_spacing.dart';

/// Skeleton / shimmer placeholder for async content loading.
class EnpixSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const EnpixSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = AppRadius.xs,
  });

  @override
  State<EnpixSkeleton> createState() => _EnpixSkeletonState();
}

class _EnpixSkeletonState extends State<EnpixSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = 0.3 + (_controller.value * 0.3);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.fillPrimary.withAlpha((opacity * 255).toInt()),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

/// Grid of skeleton thumbnails for photo gallery loading.
class EnpixSkeletonGrid extends StatelessWidget {
  final int itemCount;
  final int crossAxisCount;
  final double spacing;

  const EnpixSkeletonGrid({
    super.key,
    this.itemCount = 12,
    this.crossAxisCount = 3,
    this.spacing = 2,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final tileSize =
        (screenWidth - spacing * (crossAxisCount - 1) - 4) / crossAxisCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: 1,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return EnpixSkeleton(
            width: tileSize,
            height: tileSize,
          );
        },
      ),
    );
  }
}
