/// Compile-time feature flags.
///
/// `const` so a `false` flag is dead-code-eliminated in release builds.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Gates the whole plugin system. When `false` the plugin UI is shown as
/// visibly unavailable and every playback entry point short-circuits.
///
/// See `docs/architecture/PLUGINS.md#feature-gating`.
const bool kPluginsEnabled = false;

/// "Playback is disabled in this build" snackbar, shown from every
/// `/player` entry point when [kPluginsEnabled] is `false`.
void showPlaybackUnavailableSnack(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('Playback is disabled in this build'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceDark,
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.navBarHorizontal,
          0,
          AppSpacing.navBarHorizontal,
          AppSpacing.navBarBottom + 80,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
}
