import 'package:flutter/material.dart';
import 'package:enpix/core/theme/context_ext.dart';

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
        color: backgroundColor ?? context.colors.fillPrimary,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: valueColor ?? context.colors.brandBlue,
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
          color ?? context.colors.brandBlue,
        ),
      ),
    );
  }
}

/// Enpix mini progress bar - gradient fill, iOS 18 style.
class EnpixMiniProgress extends StatelessWidget {
  final double value;

  const EnpixMiniProgress({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: context.colors.fillPrimary,
        borderRadius: BorderRadius.circular(3),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [context.colors.brandBlue, context.colors.brandTeal],
            ),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}
