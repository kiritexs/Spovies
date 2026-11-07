import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';

/// Stand-in for a section that failed to load: its title (if any) and a
/// Retry button. Riverpod's automatic retry is off app-wide, so every
/// failed section needs one of these.
class RetryRow extends StatelessWidget {
  final String title;
  final VoidCallback onRetry;

  const RetryRow({super.key, this.title = '', required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.sectionPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(title, style: AppTextStyles.sectionTitle),
            const SizedBox(height: 16),
          ],
          Center(
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Couldn\'t load. Retry'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
