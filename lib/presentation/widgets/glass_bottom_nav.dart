import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Floating glass bottom navigation bar with 4 tabs and active dot indicator.
class GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    _NavItem(icon: Icons.home_rounded, label: 'Home'),
    _NavItem(icon: Icons.explore_outlined, label: 'Explore'),
    _NavItem(icon: Icons.confirmation_number_outlined, label: 'Browse'),
    _NavItem(icon: Icons.person_outlined, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppSpacing.borderRadius2Xl,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.glassGradient,
            borderRadius: AppSpacing.borderRadius2Xl,
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: AppColors.navBarShadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              _items.length,
              (index) => _buildTab(index),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(int index) {
    final isActive = index == currentIndex;
    final item = _items[index];

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isActive ? 1.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive ? _getFilledIcon(item.icon) : item.icon,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
                size: AppSpacing.iconLg,
              ),
            ),
            if (isActive) ...[
              const SizedBox(height: 6),
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ] else
              const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// Map outline icons to their filled variants for active state.
  IconData _getFilledIcon(IconData icon) {
    return switch (icon) {
      Icons.home_rounded => Icons.home_rounded,
      Icons.explore_outlined => Icons.explore_rounded,
      Icons.confirmation_number_outlined => Icons.confirmation_number_rounded,
      Icons.person_outlined => Icons.person_rounded,
      _ => icon,
    };
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
