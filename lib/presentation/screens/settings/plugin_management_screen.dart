import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/errors/plugin_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../domain/entities/plugin_manifest.dart';
import '../../providers/plugin_providers.dart';

// ignore_for_file: use_build_context_synchronously

/// Plugin management screen — add, view, and remove plugins.
///
/// Features:
/// - List of installed plugins with icon, name, version, hooks
/// - "Add Plugin" FAB → glass bottom sheet with URL input
/// - Swipe-to-delete with confirmation
/// - Loading / error / success states
///
/// When [kPluginsEnabled] is `false`, the whole management UI is
/// replaced with a friendly placeholder — the tile that opened this
/// screen is already hidden in Settings, but state-restoration, saved
/// links, or manual `/plugins` URLs could still land users here.
class PluginManagementScreen extends ConsumerWidget {
  const PluginManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kPluginsEnabled) return const _PluginsDisabledView();

    final pluginsAsync = ref.watch(installedPluginsProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        title: Text('Plugins', style: AppTextStyles.appTitle),
        centerTitle: false,
      ),
      body: pluginsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Failed to load plugins: $e',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (plugins) => plugins.isEmpty
            ? _buildEmptyState()
            : _buildPluginList(context, ref, plugins),
      ),
      floatingActionButton: _buildAddFab(context, ref),
    );
  }

  // ─── Empty State ────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.extension_off_rounded,
            size: 64,
            color: AppColors.textSecondary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No plugins installed',
            style: AppTextStyles.cardTitle.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to add a plugin or a registry URL (one link for multiple plugins)',
            style: AppTextStyles.cardSubtitle,
          ),
        ],
      ),
    );
  }

  // ─── Plugin List ────────────────────────────────────────────────────────

  Widget _buildPluginList(
    BuildContext context,
    WidgetRef ref,
    List<PluginManifest> plugins,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.xl),
      itemCount: plugins.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final plugin = plugins[index];
        return Dismissible(
          key: ValueKey(plugin.pluginId),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: const Icon(Icons.delete_outline, color: AppColors.danger),
          ),
          confirmDismiss: (_) => _confirmUninstall(context, plugin.name),
          onDismissed: (_) {
            ref.read(pluginInstallProvider.notifier).uninstall(plugin.pluginId);
          },
          child: _PluginTile(plugin: plugin),
        );
      },
    );
  }

  // ─── Add Plugin FAB ─────────────────────────────────────────────────────

  Widget _buildAddFab(BuildContext context, WidgetRef ref) {
    return FloatingActionButton(
      onPressed: () => _showAddPluginSheet(context, ref),
      backgroundColor: AppColors.primary,
      elevation: 8,
      child: const Icon(Icons.add_rounded, color: Colors.white),
    );
  }

  // ─── Add Plugin Bottom Sheet ────────────────────────────────────────────

  void _showAddPluginSheet(BuildContext context, WidgetRef ref) {
    // The controller's lifetime is owned by _AddPluginSheetState (created in
    // initState, disposed in dispose). Creating it here would leak it every
    // time the sheet opens because nothing in this scope ever disposes it.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AddPluginSheet(),
    );
  }

  // ─── Confirm Uninstall ──────────────────────────────────────────────────

  Future<bool?> _confirmUninstall(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        title: Text('Remove Plugin', style: AppTextStyles.sectionTitle),
        content: Text(
          'Are you sure you want to remove "$name"?',
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.label.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Remove',
              style: AppTextStyles.label.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Plugin Tile ──────────────────────────────────────────────────────────────

class _PluginTile extends ConsumerWidget {
  final PluginManifest plugin;

  const _PluginTile({required this.plugin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledMap = ref.watch(pluginEnabledProvider);
    final isEnabled = enabledMap[plugin.pluginId] ?? true;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: isEnabled
                ? AppColors.glassGradient
                : LinearGradient(
                    colors: [
                      AppColors.surfaceDark.withValues(alpha: 0.4),
                      AppColors.surfaceDark.withValues(alpha: 0.2),
                    ],
                  ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(
              color: isEnabled
                  ? AppColors.glassBorder
                  : AppColors.glassBorder.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Plugin icon
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: isEnabled ? 1.0 : 0.4,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusBase,
                        ),
                      ),
                      child: const Icon(
                        Icons.extension_rounded,
                        color: AppColors.primaryOnDark,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Name + version
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: isEnabled ? 1.0 : 0.5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(plugin.name, style: AppTextStyles.cardTitle),
                          const SizedBox(height: 2),
                          Text(
                            'v${plugin.version} • ${plugin.actionType.value}',
                            style: AppTextStyles.cardSubtitle,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Enable / Disable toggle
                  Switch(
                    value: isEnabled,
                    onChanged: (_) => ref
                        .read(pluginEnabledProvider.notifier)
                        .toggle(plugin.pluginId),
                    activeThumbColor: AppColors.primary,
                    inactiveThumbColor: AppColors.textMuted,
                    inactiveTrackColor: AppColors.surfaceDark.withValues(
                      alpha: 0.8,
                    ),
                  ),
                ],
              ),

              // Hook chips + swipe hint
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: isEnabled ? 1.0 : 0.4,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: plugin.hooks.map((h) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              h.value,
                              style: AppTextStyles.cardSubtitle.copyWith(
                                color: AppColors.primaryOnDark,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.swipe_left_rounded,
                    color: AppColors.textMuted.withValues(alpha: 0.35),
                    size: 16,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Add Plugin Bottom Sheet Widget ───────────────────────────────────────

class _AddPluginSheet extends ConsumerStatefulWidget {
  const _AddPluginSheet();

  @override
  ConsumerState<_AddPluginSheet> createState() => _AddPluginSheetState();
}

class _AddPluginSheetState extends ConsumerState<_AddPluginSheet> {
  late final TextEditingController _controller;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radius2Xl),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            decoration: BoxDecoration(
              gradient: AppColors.glassGradient,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppSpacing.radius2Xl),
              ),
              border: const Border(
                top: BorderSide(color: AppColors.glassBorder),
                left: BorderSide(color: AppColors.glassBorder),
                right: BorderSide(color: AppColors.glassBorder),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text('Add Plugin', style: AppTextStyles.sectionTitle),
                const SizedBox(height: 8),
                Text(
                  'Enter one link: a single plugin manifest URL, or a registry URL that returns multiple plugins (JSON array or object with "plugins" array).',
                  style: AppTextStyles.cardSubtitle,
                ),
                const SizedBox(height: 20),

                // URL Input
                TextField(
                  controller: _controller,
                  autofocus: true,
                  style: AppTextStyles.body,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: 'https://.../plugin.json or .../plugins.json',
                    hintStyle: AppTextStyles.body.copyWith(
                      color: AppColors.textMuted,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusBase,
                      ),
                      borderSide: const BorderSide(
                        color: AppColors.glassBorder,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusBase,
                      ),
                      borderSide: const BorderSide(
                        color: AppColors.glassBorder,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusBase,
                      ),
                      borderSide: const BorderSide(
                        color: AppColors.primaryOnDark,
                        width: 1.5,
                      ),
                    ),
                    prefixIcon: const Icon(
                      Icons.link_rounded,
                      color: AppColors.textSecondary,
                    ),
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 20),

                // Install Button
                SizedBox(
                  height: AppSpacing.buttonHeight,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _onInstall,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.primary.withValues(
                        alpha: 0.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusBase,
                        ),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text('Install Plugin', style: AppTextStyles.label),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onInstall() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Please enter a URL');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final installed = await ref
          .read(pluginInstallProvider.notifier)
          .installFromRegistry(url);
      if (mounted) {
        Navigator.pop(context);
        final count = installed.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count == 0
                  ? 'No new plugins to install (all already installed).'
                  : count == 1
                  ? '${installed.single.name} installed successfully!'
                  : '$count plugins installed successfully!',
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
            ),
          ),
        );
      }
    } on PluginException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Unexpected error: $e';
        });
      }
    }
  }
}

// ─── Disabled-state placeholder ───────────────────────────────────────────────

/// Shown when [kPluginsEnabled] is `false` and the user still lands on
/// `/plugins` (state restoration, deep link, manual push). Keeps a real
/// AppBar with a back button so they can leave normally.
class _PluginsDisabledView extends StatelessWidget {
  const _PluginsDisabledView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        title: Text('Plugins', style: AppTextStyles.appTitle),
        centerTitle: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.extension_off_rounded,
                size: 64,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Plugins are disabled in this build',
                style: AppTextStyles.cardTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The plugin system is disabled in this build. Watchlist, '
                'history, and browsing continue to work normally.',
                style: AppTextStyles.cardSubtitle,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
