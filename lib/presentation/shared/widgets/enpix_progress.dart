import 'package:flutter/material.dart';
import 'package:enpix/core/theme/app_colors.dart';

/// Enpix linear progress bar — iOS 18 style.
class EnpixLinearProgress extends StatelessWidget {
  final double value;
  final Color? backgroundColor;
  final Color? valueColor;
  final double height;

  const EnpixLinearProgress({
    super.key,
    required this.value,
    this.backgroundColor,
    this.valueColor,
    this.height = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.fillPrimary,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: valueColor ?? AppColors.brandBlue,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
  }
}

/// Enpix circular progress — iOS 18 style.
class EnpixCircularProgress extends StatelessWidget {
  final double? value;
  final Color? color;
  final double size;

  const EnpixCircularProgress({
    super.key,
    this.value,
    this.color,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: 2.5,
        valueColor: AlwaysStoppedAnimation<Color>(
          color ?? AppColors.brandBlue,
        ),
      ),
    );
  }
}
