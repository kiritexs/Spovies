import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../router/app_tabs.dart';

class DesktopSideNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const DesktopSideNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: AppColors.backgroundDark,
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xxl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                Image.asset(
                  'assets/Layer_8.png',
                  height: 32,
                  semanticLabel: 'Spovies',
                  errorBuilder: (_, _, _) => const Text(
                    'SPOVIES',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          for (final tab in AppTab.values)
            _NavItem(
              tab: tab,
              isSelected: currentIndex == tab.index,
              onTap: () => onTap(tab.index),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final AppTab tab;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.tab,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? AppColors.primaryOnDark
        : AppColors.textSecondary;
    final radius = BorderRadius.circular(12);

    // InkWell gives hover, focus and Enter/Space activation. The selected
    // tab has a tinted background and a filled icon, not just a colour.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Semantics(
        button: true,
        selected: isSelected,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            mouseCursor: SystemMouseCursors.click,
            hoverColor: Colors.white.withValues(alpha: 0.05),
            focusColor: AppColors.focus.withValues(alpha: 0.2),
            child: Ink(
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: radius,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    isSelected ? tab.selectedIcon : tab.icon,
                    color: color,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    tab.label,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: color,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
