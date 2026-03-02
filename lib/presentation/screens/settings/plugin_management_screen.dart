import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class PluginManagementScreen extends ConsumerWidget {
  const PluginManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      floatingActionButtonLocation: _FabAboveNavLocation.location,
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
            'Tap + to add a plugin by URL',
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
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final plugin = plugins[index];
        return Dismissible(
          key: ValueKey(plugin.pluginId),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.red),
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
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddPluginSheet(controller: controller),
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
              style: AppTextStyles.label.copyWith(color: Colors.red),
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
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusBase),
                      ),
                      child: const Icon(
                        Icons.extension_rounded,
                        color: AppColors.primary,
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
                    onChanged: (_) =>
                        ref.read(pluginEnabledProvider.notifier).toggle(
                              plugin.pluginId,
                            ),
                    activeColor: AppColors.primary,
                    inactiveThumbColor: AppColors.textMuted,
                    inactiveTrackColor:
                        AppColors.surfaceDark.withValues(alpha: 0.8),
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
                                color:
                                    AppColors.primary.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              h.value,
                              style: AppTextStyles.cardSubtitle.copyWith(
                                color: AppColors.primary,
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
  final TextEditingController controller;

  const _AddPluginSheet({required this.controller});

  @override
  ConsumerState<_AddPluginSheet> createState() => _AddPluginSheetState();
}

class _AddPluginSheetState extends ConsumerState<_AddPluginSheet> {
  bool _isLoading = false;
  String? _error;

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
                  'Enter the HTTPS URL of a Spovies plugin manifest',
                  style: AppTextStyles.cardSubtitle,
                ),
                const SizedBox(height: 20),

                // URL Input
                TextField(
                  controller: widget.controller,
                  autofocus: true,
                  style: AppTextStyles.body,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: 'https://example.com/plugin.json',
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
                        color: AppColors.primary,
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
    final url = widget.controller.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Please enter a URL');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final manifest = await ref
          .read(pluginInstallProvider.notifier)
          .install(url);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${manifest.name} installed successfully!'),
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

/// Positions the FAB above the shell's floating bottom nav (same clearance as list padding).
class _FabAboveNavLocation extends FloatingActionButtonLocation {
  _FabAboveNavLocation();

  static const _bottomOffset = 120.0; // clear floating nav bar
  static const _margin = 16.0;

  static const location = _FabAboveNavLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final width = scaffoldGeometry.scaffoldSize.width;
    final height = scaffoldGeometry.scaffoldSize.height;
    final fabWidth = scaffoldGeometry.floatingActionButtonSize.width;
    final fabHeight = scaffoldGeometry.floatingActionButtonSize.height;
    final end = width - fabWidth - _margin;
    final bottom = height - fabHeight - _margin - _bottomOffset;
    return Offset(end, bottom);
  }
}
