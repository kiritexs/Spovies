import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/datasources/local/hive_service.dart';
import '../../../data/services/export_import_service.dart';
import '../../providers/plugin_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/watch_history_providers.dart';
import '../../providers/watchlist_providers.dart';
import 'plugin_management_screen.dart';

/// Settings screen with glass-themed sections.
///
/// Fully functional: Plugins, Data, Appearance, Playback, About.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferredPlugin = ref.watch(preferredPluginProvider);
    final pluginsAsync = ref.watch(installedPluginsProvider);

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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              120, // clear floating nav bar
            ),
            sliver: SliverList.list(
              children: [
                // ── Plugins Section ────────────────────────────────
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

                // ── Data Section ───────────────────────────────────
                _buildSectionHeader('Data'),
                const SizedBox(height: 12),
                _buildGlassTile(
                  context,
                  icon: Icons.upload_rounded,
                  title: 'Export Data',
                  subtitle: 'Back up history, watchlist, and plugins',
                  onTap: () => _handleExport(context),
                ),
                const SizedBox(height: 8),
                _buildGlassTile(
                  context,
                  icon: Icons.download_rounded,
                  title: 'Import Data',
                  subtitle: 'Restore from a .spovies backup file',
                  onTap: () => _handleImport(context, ref),
                ),
                const SizedBox(height: 8),
                _buildGlassTile(
                  context,
                  icon: Icons.history_rounded,
                  title: 'Clear Watch History',
                  subtitle: 'Remove all watch progress',
                  onTap: () =>
                      _confirmClear(context, ref, 'watch history', () async {
                        await HiveService.watchHistoryBox.clear();
                        ref.invalidate(continueWatchingProvider);
                      }),
                ),
                const SizedBox(height: 8),
                _buildGlassTile(
                  context,
                  icon: Icons.bookmark_remove_rounded,
                  title: 'Clear Watchlist',
                  subtitle: 'Remove all saved items',
                  onTap: () =>
                      _confirmClear(context, ref, 'watchlist', () async {
                        await HiveService.watchlistBox.clear();
                        ref.invalidate(watchlistProvider);
                      }),
                ),

                const SizedBox(height: AppSpacing.sectionGap),

                // ── Appearance Section ─────────────────────────────
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

                // ── Playback Section ──────────────────────────────
                _buildSectionHeader('Playback'),
                const SizedBox(height: 12),
                _buildPreferredProvider(
                  context,
                  ref,
                  pluginsAsync,
                  preferredPlugin,
                ),

                const SizedBox(height: AppSpacing.sectionGap),

                // ── About Section ─────────────────────────────────
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
                const SizedBox(height: 8),
                _buildGlassTile(
                  context,
                  icon: Icons.gavel_rounded,
                  title: 'Open Source Licenses',
                  subtitle: 'View third-party library licenses',
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Spovies',
                    applicationVersion: '1.0.0',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Section Header ─────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: AppTextStyles.welcomeLabel.copyWith(
        letterSpacing: 2,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  // ─── Glass Tile ─────────────────────────────────────────────────────

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

  // ─── Preferred Provider ────────────────────────────────────────────

  Widget _buildPreferredProvider(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<dynamic>> pluginsAsync,
    String? current,
  ) {
    final plugins = pluginsAsync.when(
      data: (list) => list,
      loading: () => <dynamic>[],
      error: (_, __) => <dynamic>[],
    );

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
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
              ),
              child: const Icon(
                Icons.play_circle_outline,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            title: Text('Preferred Provider', style: AppTextStyles.cardTitle),
            subtitle: Text(
              current ?? 'Auto (first available)',
              style: AppTextStyles.cardSubtitle,
            ),
            trailing: DropdownButton<String?>(
              value: current,
              underline: const SizedBox.shrink(),
              dropdownColor: AppColors.surfaceDark,
              iconEnabledColor: AppColors.textSecondary,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Auto', style: TextStyle(color: Colors.white)),
                ),
                ...plugins.map(
                  (p) => DropdownMenuItem<String?>(
                    value: p.pluginId,
                    child: Text(
                      p.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
              onChanged: (value) {
                ref.read(preferredPluginProvider.notifier).set(value);
              },
            ),
          ),
        ),
      ),
    );
  }

  // ─── Actions ──────────────────────────────────────────────────────

  Future<void> _handleExport(BuildContext context) async {
    try {
      _showSnackBar(context, 'Preparing export...', isLoading: true);
      await ExportImportService.exportData();
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      if (context.mounted) {
        _showSnackBar(context, 'Export failed: $e', isError: true);
      }
    }
  }

  Future<void> _handleImport(BuildContext context, WidgetRef ref) async {
    try {
      _showSnackBar(context, 'Importing...', isLoading: true);
      final success = await ExportImportService.importData();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (success) {
        // Invalidate all data providers to refresh the UI
        ref.invalidate(continueWatchingProvider);
        ref.invalidate(watchlistProvider);
        ref.invalidate(installedPluginsProvider);
        _showSnackBar(context, 'Data imported successfully!');
      } else {
        _showSnackBar(context, 'Import cancelled or failed', isError: true);
      }
    } catch (e) {
      if (context.mounted) {
        _showSnackBar(context, 'Import failed: $e', isError: true);
      }
    }
  }

  void _confirmClear(
    BuildContext context,
    WidgetRef ref,
    String dataName,
    Future<void> Function() onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        title: Text(
          'Clear $dataName?',
          style: AppTextStyles.cardTitle.copyWith(fontSize: 18),
        ),
        content: Text(
          'This will permanently delete all $dataName data. This cannot be undone.',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await onConfirm();
              if (context.mounted) {
                _showSnackBar(
                  context,
                  '${dataName[0].toUpperCase()}${dataName.substring(1)} cleared',
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isLoading = false,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (isLoading)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade900 : AppColors.surfaceDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
        ),
        duration: isLoading
            ? const Duration(seconds: 30)
            : const Duration(seconds: 3),
      ),
    );
  }
}
