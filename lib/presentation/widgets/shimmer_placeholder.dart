import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_colors.dart';

/// Shimmer loading placeholder that matches the shape of its parent.
class ShimmerPlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const ShimmerPlaceholder({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.shimmerBase,
          borderRadius: borderRadius ?? BorderRadius.circular(12),
        ),
      ),
    );
  }
}

/// Shimmer placeholder specifically for media cards (140×210).
class MediaCardShimmer extends StatelessWidget {
  const MediaCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerPlaceholder(
            width: 140,
            height: 210,
            borderRadius: BorderRadius.circular(16),
          ),
          const SizedBox(height: 8),
          const ShimmerPlaceholder(width: 100, height: 14),
          const SizedBox(height: 4),
          const ShimmerPlaceholder(width: 70, height: 12),
        ],
      ),
    );
  }
}

/// Shimmer placeholder for the hero card (full width, 4:5).
class HeroCardShimmer extends StatelessWidget {
  const HeroCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: ShimmerPlaceholder(borderRadius: BorderRadius.circular(32)),
      ),
    );
  }
}
