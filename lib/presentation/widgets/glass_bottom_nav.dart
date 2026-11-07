import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../router/app_tabs.dart';

/// Floating glass bottom navigation bar with 4 tabs and active dot indicator.
class GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (final tab in AppTab.values) _buildTab(tab)],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(AppTab tab) {
    final isActive = tab.index == currentIndex;

    // The bar shows icons only, so the label goes to screen readers
    // (Semantics) and to long-press / hover (Tooltip).
    return Expanded(
      child: Semantics(
        button: true,
        selected: isActive,
        label: tab.label,
        excludeSemantics: true,
        child: Tooltip(
          message: tab.label,
          excludeFromSemantics: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => onTap(tab.index),
              borderRadius: AppSpacing.borderRadiusLg,
              focusColor: AppColors.focus.withValues(alpha: 0.2),
              child: SizedBox(
                height: 48,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedScale(
                      scale: isActive ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      child: Icon(
                        isActive ? tab.selectedIcon : tab.icon,
                        color: isActive
                            ? AppColors.primaryOnDark
                            : AppColors.textSecondary,
                        size: AppSpacing.iconLg,
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryOnDark,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ] else
                      const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
