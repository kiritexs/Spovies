import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Custom title bar (drag area + window buttons) above the whole app.
///
/// Wrapped around the Navigator in `MaterialApp.builder`, so every route
/// gets it — pushed screens like Details included, and narrow windows
/// that use the mobile layout. On non-desktop platforms it is a no-op.
class DesktopWindowFrame extends StatelessWidget {
  final Widget child;

  /// Hidden for routes that draw their own window controls (the player).
  /// The bar collapses rather than leaving the tree, so [child] — the
  /// Navigator — keeps its state when this flips.
  final bool showTitleBar;

  const DesktopWindowFrame({
    super.key,
    required this.child,
    this.showTitleBar = true,
  });

  static final bool _isDesktop =
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return child;

    return Column(
      children: [
        SizedBox(
          height: showTitleBar ? _CustomTitleBar.height : 0,
          child: showTitleBar ? const _CustomTitleBar() : null,
        ),
        // Its own semantics container: a route's BlockSemantics would
        // otherwise hide the title bar (painted before it) from screen
        // readers.
        Expanded(child: Semantics(container: true, child: child)),
      ],
    );
  }
}

class _CustomTitleBar extends StatelessWidget {
  const _CustomTitleBar();

  static const double height = 32;

  @override
  Widget build(BuildContext context) {
    // Material: this sits above the Navigator, outside any Scaffold, and
    // the window buttons' InkWells need a Material ancestor.
    return Material(
      color: AppColors.backgroundDark,
      child: Row(
        children: [
          // Draggable area
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) => windowManager.startDragging(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: [
                    Image.asset('assets/Group_1.png', height: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Spovies',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Window Controls
          const _WindowButtons(),
        ],
      ),
    );
  }
}

class _WindowButtons extends StatelessWidget {
  const _WindowButtons();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowButton(
          icon: Icons.minimize_rounded,
          label: 'Minimize',
          onPressed: () => windowManager.minimize(),
        ),
        _WindowButton(
          icon: Icons.crop_square_rounded,
          label: 'Maximize',
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              unawaited(windowManager.unmaximize());
            } else {
              unawaited(windowManager.maximize());
            }
          },
        ),
        _WindowButton(
          icon: Icons.close_rounded,
          label: 'Close',
          isClose: true,
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  Widget build(BuildContext context) {
    // No Tooltip: the title bar is above the Navigator's Overlay.
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        hoverColor: isClose
            ? Colors.red.withValues(alpha: 0.8)
            : Colors.white10,
        child: SizedBox(
          width: 46,
          height: _CustomTitleBar.height,
          child: Icon(icon, size: 16, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
