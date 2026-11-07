import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/feature_flags.dart';
import '../../../domain/entities/plugin_manifest.dart';
import '../../providers/app_info_provider.dart';
import '../../widgets/app_snack_bar.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/services/export_import_service.dart';
import '../../providers/plugin_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/watch_history_providers.dart';
import '../../providers/watch_status_providers.dart';
import '../../providers/watchlist_providers.dart';

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
                //
                // Behaviour depends on [kPluginsEnabled]:
                //   • enabled  → interactive tile that opens `/plugins`
                //   • disabled → tile still shown (users know the
                //                feature exists) but visually greyed and
                //                the subtitle says "Disabled in
                //                this build"; tapping still opens
                //                `/plugins`, which then shows the
                //                friendly disabled placeholder.
                _buildSectionHeader('Plugins'),
                const SizedBox(height: 12),
                _buildGlassTile(
                  context,
                  icon: Icons.extension_rounded,
                  title: 'Manage Plugins',
                  subtitle: kPluginsEnabled
                      ? 'Add, remove, and view installed plugins'
                      : 'Disabled in this build',
                  disabled: !kPluginsEnabled,
                  onTap: () => context.push('/plugins'),
                ),

                const SizedBox(height: AppSpacing.sectionGap),

                // ── Data Section ───────────────────────────────────
                _buildSectionHeader('Data'),
                const SizedBox(height: 12),
                _buildGlassTile(
                  context,
                  icon: Icons.upload_rounded,
                  title: 'Export Data',
                  // Subtitle reflects what's actually included in the
                  // export — no point advertising plugins as backed up
                  // when the plugin system is disabled.
                  subtitle: kPluginsEnabled
                      ? 'Back up history, watchlist, and plugins'
                      : 'Back up history and watchlist',
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
                  destructive: true,
                  subtitle: 'Remove all watch progress',
                  onTap: () =>
                      _confirmClear(context, ref, 'watch history', () async {
                        await ref
                            .read(watchHistoryRepositoryProvider)
                            .clearHistory();
                        ref.invalidate(continueWatchingProvider);
                        ref.invalidate(episodeProgressProvider);
                      }),
                ),
                const SizedBox(height: 8),
                _buildGlassTile(
                  context,
                  icon: Icons.bookmark_remove_rounded,
                  title: 'Clear Library',
                  destructive: true,
                  subtitle: 'Remove all saved titles and their statuses',
                  onTap: () => _confirmClear(context, ref, 'library', () async {
                    // Statuses go too: a status with no saved title would
                    // otherwise linger invisibly.
                    ref.read(watchlistProvider.notifier).clearAll();
                    await ref
                        .read(watchStatusNotifierProvider.notifier)
                        .clearAll();
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
                  subtitle: 'Dark (only)',
                  trailing: const Icon(
                    Icons.check_circle,
                    color: AppColors.primaryOnDark,
                    size: 20,
                  ),
                ),

                const SizedBox(height: AppSpacing.sectionGap),

                // ── Playback Section ──────────────────────────────
                //
                // When [kPluginsEnabled] is false the interactive
                // "Preferred Provider" dropdown is replaced with a
                // static disabled tile — the section is still visible
                // so users understand the feature exists.
                _buildSectionHeader('Playback'),
                const SizedBox(height: 12),
                if (kPluginsEnabled)
                  _buildPreferredProvider(
                    context,
                    ref,
                    pluginsAsync,
                    preferredPlugin,
                  )
                else
                  _buildGlassTile(
                    context,
                    icon: Icons.play_circle_outline_rounded,
                    title: 'Preferred Provider',
                    subtitle: 'Disabled in this build',
                    disabled: true,
                  ),

                const SizedBox(height: AppSpacing.sectionGap),

                // ── About Section ─────────────────────────────────
                _buildSectionHeader('About'),
                const SizedBox(height: 12),
                _buildGlassTile(
                  context,
                  icon: Icons.info_outline_rounded,
                  title: 'Spovies',
                  subtitle: switch (ref.watch(appVersionProvider)) {
                    AsyncData(:final value) => 'v$value • A KIRITEX PROJECT',
                    _ => 'A KIRITEX PROJECT',
                  },
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
                  subtitle: 'Libraries and the Spline Sans font',
                  onTap: () => context.push('/licenses'),
                ),
                const SizedBox(height: AppSpacing.sectionGap + 8),

                // ── App badge ─────────────────────────────────────
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: AppColors.glassGradient,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sectionPaddingH * 3,
                      AppSpacing.sectionPaddingH,
                      AppSpacing.sectionPaddingH * 3,
                      AppSpacing.sectionPaddingH * 1.5,
                    ),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusBase,
                          ),
                          child: Image.asset(
                            'assets/logo.png',
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text('Spovies', style: AppTextStyles.cardTitle),
                        const SizedBox(height: 2),
                        Text(
                          'by Kiritex',
                          style: AppTextStyles.cardSubtitle.copyWith(
                            fontSize: 12,
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
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
    bool disabled = false,
    bool destructive = false,
  }) {
    final accent = disabled
        ? AppColors.textSecondary
        : destructive
        ? AppColors.danger
        : AppColors.primary;
    // Disabled tiles still render (the user should know the feature
    // exists) but with 50 % opacity, muted colours, and no chevron.
    // The onTap fires so the user can land on the "unavailable"
    // placeholder screen and read what's going on.
    final Widget tile = ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.glassGradient,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: AppColors.glassBorder),
          ),
          // Transparent Material so the ListTile's hover, focus and splash
          // ink paints above the glass gradient instead of behind it.
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              onTap: onTap,
              focusColor: AppColors.focus.withValues(alpha: 0.15),
              hoverColor: Colors.white.withValues(alpha: 0.04),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
                ),
                child: Icon(
                  icon,
                  color: accent == AppColors.primary
                      ? AppColors.primaryOnDark
                      : accent,
                  size: 20,
                ),
              ),
              title: Text(title, style: AppTextStyles.cardTitle),
              subtitle: Text(subtitle, style: AppTextStyles.cardSubtitle),
              trailing:
                  trailing ??
                  (disabled
                      ? const Icon(
                          Icons.block_rounded,
                          color: AppColors.textMuted,
                          size: 18,
                        )
                      : (onTap != null
                            ? const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.textSecondary,
                              )
                            : null)),
            ),
          ),
        ),
      ),
    );

    if (!disabled) return tile;
    return Opacity(opacity: 0.55, child: tile);
  }

  // ─── Preferred Provider ────────────────────────────────────────────

  Widget _buildPreferredProvider(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<PluginManifest>> pluginsAsync,
    String? current,
  ) {
    final plugins = pluginsAsync.value ?? const <PluginManifest>[];

    // If the saved preferred ID doesn't match any loaded plugin (e.g. still
    // loading, or plugin was uninstalled), fall back to null so the
    // DropdownButton's assertion is satisfied.
    final effectiveValue =
        (current != null && plugins.any((p) => p.pluginId == current))
        ? current
        : null;

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
                color: AppColors.primaryOnDark,
                size: 20,
              ),
            ),
            title: Text('Preferred Provider', style: AppTextStyles.cardTitle),
            subtitle: Text(
              effectiveValue ?? 'Auto (first available)',
              style: AppTextStyles.cardSubtitle,
            ),
            trailing: DropdownButton<String?>(
              value: effectiveValue,
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
                unawaited(
                  ref.read(preferredPluginProvider.notifier).set(value),
                );
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
      showAppSnackBar(
        context,
        'Preparing export…',
        aboveNav: true,
        showProgress: true,
        duration: const Duration(seconds: 30),
      );
      await ExportImportService.exportData();
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          'Export failed: $e',
          aboveNav: true,
          isError: true,
        );
      }
    }
  }

  Future<void> _handleImport(BuildContext context, WidgetRef ref) async {
    // Two-stage import:
    //   1. previewImport — parses the .spovies file, validates every plugin
    //      manifest, returns a summary WITHOUT touching local storage.
    //   2. confirmation dialog — shows the user exactly which plugins will
    //      be installed (and which were rejected). The plugin list is the
    //      high-risk surface; without an explicit per-plugin confirmation
    //      a hostile `.spovies` backup could silently land an `intent://`
    //      or `content://` `urlTemplate` that the user would later tap.
    //   3. applyImport — only runs on the user's positive confirmation.
    try {
      final preview = await ExportImportService.previewImport();
      if (preview == null) {
        // User cancelled the file picker — no toast needed.
        return;
      }
      if (!context.mounted) return;

      final confirmed = await _confirmImport(context, preview);
      if (!confirmed || !context.mounted) return;

      showAppSnackBar(
        context,
        'Importing…',
        aboveNav: true,
        showProgress: true,
        duration: const Duration(seconds: 30),
      );
      await ExportImportService.applyImport(preview);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Refresh every provider that surfaces imported data.
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(watchlistProvider);
      ref.invalidate(installedPluginsProvider);

      showAppSnackBar(context, 'Backup imported', aboveNav: true);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        showAppSnackBar(
          context,
          'Import failed: $e',
          aboveNav: true,
          isError: true,
        );
      }
    }
  }

  /// Per-plugin confirmation dialog. Lists names + urlTemplates so the user
  /// can see exactly what will be installed before any write occurs.
  Future<bool> _confirmImport(
    BuildContext context,
    ImportPreview preview,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        title: Text(
          'Review backup contents',
          style: AppTextStyles.cardTitle.copyWith(fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _summaryRow('Watch history', preview.watchHistoryCount),
              _summaryRow('Library', preview.watchlistCount),
              _summaryRow('Watch statuses', preview.statusCount),
              _summaryRow('Settings', preview.settingsCount),
              const SizedBox(height: 12),
              Text(
                'Plugins to install (${preview.plugins.length})',
                style: AppTextStyles.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (preview.plugins.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'None',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else
                ...preview.plugins.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• ${p.name}',
                          style: AppTextStyles.body.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '   ${p.urlTemplate}',
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              if (preview.rejectedPlugins.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Rejected (${preview.rejectedPlugins.length})',
                  style: AppTextStyles.body.copyWith(
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'These plugins failed validation and will be skipped. '
                  'A backup with invalid plugins may have been tampered with.',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Only import backups from sources you trust. Installed '
                'plugins can launch arbitrary HTTPS URLs when tapped.',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryOnDark,
            ),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _summaryRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(color: Colors.white),
            ),
          ),
          Text(
            '$count',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  void _confirmClear(
    BuildContext context,
    WidgetRef ref,
    String dataName,
    Future<void> Function() onConfirm,
  ) {
    unawaited(
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
                  showAppSnackBar(
                    context,
                    '${dataName[0].toUpperCase()}${dataName.substring(1)} cleared',
                    aboveNav: true,
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('Clear'),
            ),
          ],
        ),
      ),
    );
  }
}
