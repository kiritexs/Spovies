import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Width at which the app switches from the bottom nav to the side nav.
/// Matches the breakpoint in `MainScaffold`.
const double kDesktopBreakpoint = 800;

/// Shows the app's floating snackbar, replacing any current one.
///
/// Set [aboveNav] on the tab screens: on the mobile layout the snackbar is
/// lifted above the floating bottom nav instead of being hidden behind it.
/// A snackbar with an [action] auto-dismisses after [duration] (Flutter's
/// default would keep it until dismissed), so deferred work can commit.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  bool aboveNav = false,
  bool isError = false,
  bool showProgress = false,
  Duration duration = const Duration(seconds: 3),
}) {
  final hasBottomNav =
      aboveNav && MediaQuery.sizeOf(context).width < kDesktopBreakpoint;
  return (ScaffoldMessenger.of(context)..hideCurrentSnackBar()).showSnackBar(
    SnackBar(
      content: showProgress
          ? Row(
              children: [
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
            )
          : Text(message),
      action: action,
      persist: false,
      duration: duration,
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? Colors.red.shade900 : AppColors.surfaceDark,
      margin: EdgeInsets.fromLTRB(
        AppSpacing.navBarHorizontal,
        0,
        AppSpacing.navBarHorizontal,
        hasBottomNav
            ? AppSpacing.navBarBottom + 80
            : AppSpacing.navBarHorizontal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
      ),
    ),
  );
}

/// "Playback is disabled in this build", shown from every `/player` entry
/// point while `kPluginsEnabled` is `false`. Pass [aboveNav] from tab
/// screens (Home), not from pushed routes (Details).
void showPlaybackUnavailableSnack(
  BuildContext context, {
  bool aboveNav = false,
}) {
  showAppSnackBar(
    context,
    'Playback is disabled in this build',
    aboveNav: aboveNav,
    duration: const Duration(seconds: 2),
  );
}
