import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class DesktopWindowFrame extends StatelessWidget {
  final Widget child;

  const DesktopWindowFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Only apply custom frame on Desktop platforms (primarily Windows for now)
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    if (!isDesktop) return child;

    return Column(
      children: [
        const _CustomTitleBar(),
        Expanded(child: child),
      ],
    );
  }
}

class _CustomTitleBar extends StatelessWidget {
  const _CustomTitleBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
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
          onPressed: () => windowManager.minimize(),
        ),
        _WindowButton(
          icon: Icons.crop_square_rounded,
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
          isClose: true,
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      hoverColor: isClose ? Colors.red.withValues(alpha:0.8) : Colors.white10,
      child: SizedBox(
        width: 46,
        height: 32,
        child: Icon(icon, size: 16, color: AppColors.textSecondary),
      ),
    );
  }
}
