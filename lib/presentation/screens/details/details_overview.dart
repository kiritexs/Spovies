part of 'details_screen.dart';

// ─── Expandable Overview ──────────────────────────────────────────────────

class _ExpandableOverview extends StatefulWidget {
  final String text;
  const _ExpandableOverview({required this.text});

  @override
  State<_ExpandableOverview> createState() => _ExpandableOverviewState();
}

class _ExpandableOverviewState extends State<_ExpandableOverview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedCrossFade(
        firstChild: Text(
          widget.text,
          style: AppTextStyles.body.copyWith(
            color: AppColors.textSecondary,
            height: 1.6,
          ),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        secondChild: Text(
          widget.text,
          style: AppTextStyles.body.copyWith(
            color: AppColors.textSecondary,
            height: 1.6,
          ),
        ),
        crossFadeState: _expanded
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        duration: const Duration(milliseconds: 300),
      ),
    );
  }
}
