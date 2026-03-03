import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';

/// Fixed header with gradient fade, "Welcome back" label, app title, and search.
class AppHeader extends StatelessWidget {
  final VoidCallback? onSearchTap;

  const AppHeader({super.key, this.onSearchTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(
        left: AppSpacing.sectionPaddingH,
        right: AppSpacing.sectionPaddingH,
        top: AppSpacing.headerPaddingTop,
        bottom: 16,
      ),
      decoration: const BoxDecoration(gradient: AppColors.headerGradient),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left: Welcome + App name
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('WELCOME BACK', style: AppTextStyles.welcomeLabel),
                const SizedBox(height: 2),
                Image.asset(
                  'assets/Layer_8.png',
                  height: 32,
                  fit: BoxFit.contain,
                ),
              ],
            ),

            // Right: Search button
            _buildSearchButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchButton() {
    return Container(
      width: AppSpacing.searchButtonSize,
      height: AppSpacing.searchButtonSize,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onSearchTap,
          child: const Icon(
            Icons.search,
            color: Colors.white,
            size: AppSpacing.iconMd,
          ),
        ),
      ),
    );
  }
}
