import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import 'plugin_management_screen.dart';

/// Settings screen with glass-themed sections.
///
/// Phase 2: Only the Plugins section is active.
/// Phase 5 will complete Appearance, Data, and About sections.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: CustomScrollView(
        slivers: [
          // ─── App Bar ──────────────────────────────────────────────
          SliverAppBar(
            floating: true,
            backgroundColor: AppColors.backgroundDark,
            surfaceTintColor: Colors.transparent,
            title: Text('Settings', style: AppTextStyles.appTitle),
            centerTitle: false,
          ),

          // ─── Body ─────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            sliver: SliverList.list(
              children: [
                // ── Plugins Section ─────────────────────────────────
                _buildSectionHeader('Plugins'),
                const SizedBox(height: 12),
                _buildGlassTile(
                  context,
                  icon: Icons.extension_rounded,
                  title: 'Manage Plugins',
                  subtitle: 'Add, remove, and view installed plugins',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PluginManagementScreen(),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.sectionGap),

                // ── Appearance Section (Stub) ───────────────────────
                _buildSectionHeader('Appearance'),
                const SizedBox(height: 12),
                _buildGlassTile(
                  context,
                  icon: Icons.palette_outlined,
                  title: 'Theme',
                  subtitle: 'Dark',
                  trailing: const Icon(
                    Icons.check_circle,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),

                const SizedBox(height: AppSpacing.sectionGap),

                // ── About Section ───────────────────────────────────
                _buildSectionHeader('About'),
                const SizedBox(height: 12),
                _buildGlassTile(
                  context,
                  icon: Icons.info_outline_rounded,
                  title: 'Spovies',
                  subtitle: 'v1.0.0 • Powered by TMDB',
                ),
                const SizedBox(height: 8),
                _buildGlassTile(
                  context,
                  icon: Icons.description_outlined,
                  title: 'TMDB Attribution',
                  subtitle:
                      'This product uses the TMDB API but is not endorsed or certified by TMDB.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: AppTextStyles.welcomeLabel.copyWith(
        letterSpacing: 2,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildGlassTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.glassGradient,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: ListTile(
            onTap: onTap,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            title: Text(title, style: AppTextStyles.cardTitle),
            subtitle: Text(subtitle, style: AppTextStyles.cardSubtitle),
            trailing:
                trailing ??
                (onTap != null
                    ? const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textSecondary,
                      )
                    : null),
          ),
        ),
      ),
    );
  }
}
