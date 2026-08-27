/// Compile-time feature flags.
///
/// Keep these as `const` so a `false` flag is dead-code-eliminated in
/// release builds — the plugin code paths behind [kPluginsEnabled]
/// won't ship in the binary when the flag is off.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// When `false`, the entire plugin system is hidden from the UI and the
/// playback entry points (Watch button, Continue Watching's play tap,
/// next-episode auto-advance) short-circuit with a "playback is
/// currently unavailable" snackbar.
///
/// What this gate covers:
///   • Settings → "Manage Plugins" tile — hidden.
///   • Settings → "Preferred Provider" section — hidden.
///   • Details → Watch Movie / Watch Series button — the button never
///     renders (no plugin means no `activePlugin`, its usual guard),
///     and if a stale `activePlugin` reference ever slipped through,
///     [_executePlugin] would still be short-circuited by this flag.
///   • Home → Continue Watching cards' onContinueTap — snackbar.
///   • DetailsScreen → episode item onPlay — no play plugin resolved.
///   • /plugins deep link — screen renders a friendly "unavailable"
///     placeholder instead of the management UI.
///   • /player deep link — every push site is gated; even if a URL
///     survived state restoration and pushed the route, the shim in
///     [pushPlayerIfEnabled] would refuse it.
///
/// Flip to `true` to re-enable everything. Nothing else in the code
/// needs to change — the flag reads are pure conditional expressions
/// with no side-effects.
const bool kPluginsEnabled = false;

/// User-facing shim for every `/player` push site.
///
/// - When [kPluginsEnabled] is `true`: pushes the route as before.
/// - When `false`: pops a floating snackbar telling the user playback
///   isn't available, and returns without navigating.
///
/// Centralising this here means the flag has to be checked in exactly
/// one place instead of at every `_executePlugin` / `_openFromStart` /
/// `_openContinue` / etc. call site.
void showPlaybackUnavailableSnack(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('Playback is currently unavailable'),
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
