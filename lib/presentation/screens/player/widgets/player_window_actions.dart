import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/player_platform.dart';

/// Top-right action row over the WebView: Windows-only drag-to-move strip,
/// optional fullscreen toggle (Windows), and the always-present close
/// button.
///
/// Extracted from `webview_player_screen.dart` so the player chrome layout
/// can evolve without touching the WebView lifecycle code.
class PlayerWindowActions extends StatelessWidget {
  const PlayerWindowActions({
    super.key,
    required this.showControls,
    required this.isFullScreen,
    required this.onToggleFullScreen,
    required this.onDismiss,
  });

  /// Drives the AnimatedOpacity + IgnorePointer wrapper — the player hides
  /// these actions after a few seconds of inactivity.
  final bool showControls;

  /// Current windowed-vs-fullscreen state on Windows. Determines the icon
  /// shown on the toggle button.
  final bool isFullScreen;

  /// Tapped by the user from the Windows fullscreen toggle. Ignored on
  /// other platforms (the toggle button is hidden there).
  final VoidCallback onToggleFullScreen;

  /// Tapped by the user from the close (×) button.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 50,
      right: 100,
      child: AnimatedOpacity(
        opacity: showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: IgnorePointer(
          ignoring: !showControls,
          child: Row(
            children: [
              // Windows: a tall transparent drag-strip so the user can move
              // the window by dragging anywhere in the title-bar zone.
              // Other platforms: empty Spacer keeps the close button
              // right-aligned.
              if (PlayerPlatform.isWindows)
                const Expanded(
                  child: DragToMoveArea(child: SizedBox(height: 60)),
                )
              else
                const Spacer(),

              Padding(
                padding: const EdgeInsets.only(top: 12, right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (PlayerPlatform.isWindows) ...[
                      _ActionButton(
                        icon: isFullScreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        onTap: onToggleFullScreen,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _ActionButton(icon: Icons.close_rounded, onTap: onDismiss),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusBase),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}
